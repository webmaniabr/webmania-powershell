using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Management.Automation;
using System.Reflection;
using System.Numerics;
using System.Threading;
using System.Threading.Tasks;
using Webmania;

namespace Webmania.PowerShell;

// Never retains rejected input. PowerShell's later typed conversion can format
// this value safely, including its nested ParameterBinding exception messages.
public sealed class ProtectedInvalidInput {
    internal static readonly ProtectedInvalidInput Instance = new();
    private ProtectedInvalidInput() { }
    public override string ToString() => "[protected-invalid-input]";
}
[AttributeUsage(AttributeTargets.Property | AttributeTargets.Field | AttributeTargets.Parameter)]
public sealed class SafeTypeAttribute(Type expectedType) : ArgumentTransformationAttribute {
    public override object Transform(EngineIntrinsics engineIntrinsics, object inputData) {
        object value = inputData is PSObject wrapped ? wrapped.BaseObject : inputData;
        if (expectedType == typeof(string)) return StringScalar(value);
        if (value is null || expectedType.IsInstanceOfType(value)) return value!;
        if (expectedType == typeof(SwitchParameter) && value is bool flag) return new SwitchParameter(flag);
        return ProtectedInvalidInput.Instance;
    }
    // String conversion is a separate trust boundary: a general sentinel is
    // convertible to string and could become a filename. Reject unknown values
    // inside the transformation instead. Never call their ToString/IConvertible.
    private static object StringScalar(object? value) => value switch {
        null => null!,
        string text => text,
        char character => character.ToString(),
        bool flag => flag ? bool.TrueString : bool.FalseString,
        byte number => number.ToString(CultureInfo.InvariantCulture),
        sbyte number => number.ToString(CultureInfo.InvariantCulture),
        short number => number.ToString(CultureInfo.InvariantCulture),
        ushort number => number.ToString(CultureInfo.InvariantCulture),
        int number => number.ToString(CultureInfo.InvariantCulture),
        uint number => number.ToString(CultureInfo.InvariantCulture),
        long number => number.ToString(CultureInfo.InvariantCulture),
        ulong number => number.ToString(CultureInfo.InvariantCulture),
        Int128 number => number.ToString(CultureInfo.InvariantCulture),
        UInt128 number => number.ToString(CultureInfo.InvariantCulture),
        IntPtr number => number.ToString("D",CultureInfo.InvariantCulture),
        UIntPtr number => number.ToString("D",CultureInfo.InvariantCulture),
        BigInteger number => number.ToString(CultureInfo.InvariantCulture),
        decimal number => number.ToString(CultureInfo.InvariantCulture),
        float number => number.ToString("R",CultureInfo.InvariantCulture),
        double number => number.ToString("R",CultureInfo.InvariantCulture),
        Half number => number.ToString("R",CultureInfo.InvariantCulture),
        _ => throw new ArgumentTransformationMetadataException("Expected a literal string or a supported native scalar; unsafe conversion was rejected.")
    };
}

// SDK batch preparation/iterator boundaries may cancel before an engine diagnostic
// exists. Preserve that native cancellation as a fixed safe cancellation record,
// without converting it into LocalValidation or retaining arbitrary exception text.
public sealed class WebmaniaPowerShellCancellationException(string operationId) : OperationCanceledException("Webmania invocation canceled before further helper work.") {
    public string OperationId { get; } = operationId;
    public string Kind => "cancelled";
    public bool OutcomeUncertain => false;
    public string RecoveryAdvice => "No automatic replay was performed. Resume only with an explicit new invocation.";
    public override string ToString() => $"WebmaniaPowerShellCancellationException({OperationId}) [redacted]";
}

// Imported privately by the script module. The script-facing command parameters
// remain the exact typed DTOs. This cmdlet owns synchronous invocation lifetime;
// StopProcessing cancels a linked token created BEFORE any SDK dispatch.
[Cmdlet(VerbsLifecycle.Invoke, "WebmaniaInternalCall")]
public sealed class InvokeInternalCallCommand : PSCmdlet {
    [Parameter(Mandatory=true), SafeType(typeof(WebmaniaClient))] public WebmaniaClient Client { get; set; } = null!;
    [Parameter(Mandatory=true), SafeType(typeof(string))] public string MethodName { get; set; } = "";
    [Parameter(Mandatory=true), SafeType(typeof(object))] public object Parameters { get; set; } = null!;
    [Parameter, SafeType(typeof(CancellationToken))] public CancellationToken CancellationToken { get; set; }
    [Parameter, SafeType(typeof(PollOptions))] public PollOptions PollOptions { get; set; } = new();
    [Parameter, SafeType(typeof(int))] public int MaximumPages { get; set; } = 100;
    [Parameter, SafeType(typeof(int))] public int MaximumItems { get; set; } = 100;
    [Parameter, SafeType(typeof(object))] public object? Continuation { get; set; }
    [Parameter, SafeType(typeof(SwitchParameter))] public SwitchParameter AsTask { get; set; }
    private readonly object gate = new();
    private CancellationTokenSource? invocation;
    private bool stopRequested;
    private static readonly HashSet<string> Operations = WebmaniaClient.Operations
        .Select(op => char.ToUpperInvariant(op.Id[0])+op.Id[1..]+"Async").ToHashSet(StringComparer.Ordinal);
    private static readonly HashSet<string> Iterators = new(StringComparer.Ordinal) {
        "IterateMonitorCompaniesAsync", "IterateMonitorCompanyMunicipalitiesAsync", "IterateMonitorReportsAsync"
    };

    private static readonly HashSet<string> Waiters = new(StringComparer.Ordinal) { "PollFiscalReportAsync", "WaitMonitorImportAsync" };
    private static readonly HashSet<string> BatchReaders = new(StringComparer.Ordinal) {
        "ReadMonitorCompaniesAsync", "ReadMonitorCompanyMunicipalitiesAsync", "ReadMonitorReportsAsync"
    };

    protected override void BeginProcessing() {
        lock(gate) {
            if (!AsTask) invocation = CancellationTokenSource.CreateLinkedTokenSource(CancellationToken);
            if (stopRequested) invocation?.Cancel();
        }
    }
    protected override void StopProcessing() {
        lock(gate) { stopRequested=true; invocation?.Cancel(); }
    }
    protected override void ProcessRecord() {
        try {
            if (stopRequested || Stopping) throw new PipelineStoppedException();
            var token = AsTask ? CancellationToken : invocation!.Token;
            var method = typeof(WebmaniaClient).GetMethod(MethodName, BindingFlags.Public|BindingFlags.Instance);
            if (method is null || !(Operations.Contains(MethodName) || Iterators.Contains(MethodName) || Waiters.Contains(MethodName) || BatchReaders.Contains(MethodName)))
                throw new ArgumentException("Unrecognized pinned facade.");
            if (!method.GetParameters()[0].ParameterType.IsInstanceOfType(Parameters))
                throw new ArgumentException("Expected exact typed parameters.");
            object? result;
            if (Iterators.Contains(MethodName)) {
                if (AsTask) throw new ArgumentException("Iterator is synchronous pipeline output.");
                result=method.Invoke(Client, [Parameters, MaximumPages, token]);
                var itemType=method.ReturnType.GenericTypeArguments[0];
                typeof(InvokeInternalCallCommand).GetMethod(nameof(Enumerate), BindingFlags.NonPublic|BindingFlags.Instance)!
                    .MakeGenericMethod(itemType).Invoke(this,[result,token]);
            } else {
                if (BatchReaders.Contains(MethodName) && Continuation is not null && !method.GetParameters()[2].ParameterType.IsInstanceOfType(Continuation))
                    throw new ArgumentException("Expected exact typed continuation.");
                result=method.Invoke(Client, Waiters.Contains(MethodName) ? [Parameters,PollOptions,token] :
                    BatchReaders.Contains(MethodName) ? [Parameters,MaximumItems,Continuation,MaximumPages,token] : [Parameters,token]);
                var task=(Task)result!;
                if (AsTask) { WriteObject(task,false); return; }
                task.GetAwaiter().GetResult();
                WriteObject(method.ReturnType.GenericTypeArguments.Length == 1 ? task.GetType().GetProperty("Result")!.GetValue(task) : null,false);
            }
        } catch(Exception error) {
            while(error is TargetInvocationException && error.InnerException is not null) error=error.InnerException;
            if (error is PipelineStoppedException || stopRequested || Stopping) throw new PipelineStoppedException();
            var sdk = error as WebmaniaException ?? (error as WebmaniaCancellationException)?.Diagnostic;
            if (sdk is not null) {
                var record=new ErrorRecord(sdk,"Webmania."+sdk.Kind,ErrorCategory.InvalidOperation,null);
                record.ErrorDetails=new ErrorDetails(sdk+"\n"+sdk.RecoveryAdvice);
                ThrowTerminatingError(record);
            } else if (error is OperationCanceledException) {
                var operationId = MethodName switch {
                    "IterateMonitorCompaniesAsync" or "ReadMonitorCompaniesAsync" => "monitorListCompanies",
                    "IterateMonitorCompanyMunicipalitiesAsync" or "ReadMonitorCompanyMunicipalitiesAsync" => "monitorListCompanyMunicipalities",
                    "IterateMonitorReportsAsync" or "ReadMonitorReportsAsync" => "monitorListReports",
                    "WaitMonitorImportAsync" => "monitorGetImportStatus",
                    "PollFiscalReportAsync" => "fiscalCreateOrPollReport",
                    _ => char.ToLowerInvariant(MethodName[0]) + MethodName[1..^5]
                };
                var safe = new WebmaniaPowerShellCancellationException(operationId);
                ThrowTerminatingError(new ErrorRecord(safe,"Webmania.cancelled",ErrorCategory.OperationStopped,null) { ErrorDetails = new ErrorDetails(safe+"\n"+safe.RecoveryAdvice) });
            } else {
                ThrowTerminatingError(new ErrorRecord(new InvalidOperationException("Webmania input or local operation failed. Check typed parameters, credential values and client options."),"Webmania.LocalValidation",ErrorCategory.InvalidArgument,null));
            }
        } finally {
            lock(gate) { invocation?.Dispose(); invocation=null; }
        }
    }
    private void Enumerate<T>(IAsyncEnumerable<T> enumerable, CancellationToken token) {
        var iterator=enumerable.GetAsyncEnumerator(token);
        Exception? firstFailure=null;
        try {
            while(iterator.MoveNextAsync().AsTask().GetAwaiter().GetResult()) {
                token.ThrowIfCancellationRequested();
                WriteObject(iterator.Current,false);
            }
        } catch(Exception error) { firstFailure=error; throw; }
        finally {
            // Complete cancellation cleanup before the invocation lifetime ends.
            // A cleanup error must not replace the original SDK/pipeline failure.
            try { iterator.DisposeAsync().AsTask().GetAwaiter().GetResult(); }
            catch when(firstFailure is not null) { }
        }
    }
}
