using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Security;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

// Retained independent alpha1-review fixture, reused here as an author regression
// fixture. This reuse is not new independent evidence. Actual sockets, no SDK hooks.
public static class LifecycleCancellation {
 public static long CancellationTimestamp;
 public static Task AfterRequest(IndependentServer server,CancellationTokenSource cancellation,int count) => Task.Run(()=>{
  if(!server.WaitCount(count,4000))throw new Exception("No held request arrived for cancellation");
  Thread.Sleep(30);Interlocked.Exchange(ref CancellationTimestamp,Stopwatch.GetTimestamp());cancellation.Cancel();
 });
}
public sealed class IndependentReply {
 public int Status=200; public string Media="application/json"; public string Body="{}";
 public bool Hold; public Dictionary<string,string> Headers=new();
}
public sealed class IndependentRequest {
 public int Sequence; public string Method {get;set;} public string Target {get;set;}
 public Dictionary<string,string> Headers {get;set;} public string Body {get;set;}
 public long ReceivedMs {get;set;} public long ClosedMs {get;set;} = -1;
}
public sealed class IndependentServer : IDisposable {
 readonly TcpListener listener; readonly CancellationTokenSource stop=new(); readonly Stopwatch clock=Stopwatch.StartNew();
 readonly ConcurrentQueue<IndependentReply> replies=new(); readonly ConcurrentQueue<IndependentRequest> requests=new();
 readonly X509Certificate2 leaf; public X509Certificate2 Root {get;}
 public string Url {get;} public IndependentRequest[] Requests => requests.ToArray(); public int Count=>requests.Count;
 public IndependentServer(bool tls=false) {
  if(tls) {
   using var key=RSA.Create(2048); var ca=new CertificateRequest("CN=Independent Review CA",key,HashAlgorithmName.SHA256,RSASignaturePadding.Pkcs1);
   ca.CertificateExtensions.Add(new X509BasicConstraintsExtension(true,false,0,true));
   ca.CertificateExtensions.Add(new X509KeyUsageExtension(X509KeyUsageFlags.KeyCertSign,true));
   Root=ca.CreateSelfSigned(DateTimeOffset.UtcNow.AddDays(-1),DateTimeOffset.UtcNow.AddDays(2));
   using var lk=RSA.Create(2048); var req=new CertificateRequest("CN=localhost",lk,HashAlgorithmName.SHA256,RSASignaturePadding.Pkcs1);
   var san=new SubjectAlternativeNameBuilder(); san.AddIpAddress(IPAddress.Loopback);san.AddDnsName("localhost");
   req.CertificateExtensions.Add(san.Build());req.CertificateExtensions.Add(new X509BasicConstraintsExtension(false,false,0,true));
   req.CertificateExtensions.Add(new X509EnhancedKeyUsageExtension(new OidCollection{new Oid("1.3.6.1.5.5.7.3.1")},true));
   using var signed=req.Create(Root,DateTimeOffset.UtcNow.AddHours(-1),DateTimeOffset.UtcNow.AddDays(1),RandomNumberGenerator.GetBytes(16));
   leaf=signed.CopyWithPrivateKey(lk);
  }
  listener=new TcpListener(IPAddress.Loopback,0);listener.Start();Url=$"{(tls?"https":"http")}://127.0.0.1:{((IPEndPoint)listener.LocalEndpoint).Port}/";
  _=Task.Run(async()=>{while(!stop.IsCancellationRequested)try{var c=await listener.AcceptTcpClientAsync(stop.Token);_=Task.Run(()=>Handle(c));}catch(OperationCanceledException){break;}});
 }
 public void Enqueue(IndependentReply reply)=>replies.Enqueue(reply);
 public bool WaitCount(int count,int milliseconds){var sw=Stopwatch.StartNew();while(Count<count && sw.ElapsedMilliseconds<milliseconds)Thread.Sleep(5);return Count>=count;}
 async Task Handle(TcpClient client) {
  using(client) { Stream stream=client.GetStream(); IndependentRequest r=null;
   try {
    if(leaf!=null){var ssl=new SslStream(stream,false);await ssl.AuthenticateAsServerAsync(new SslServerAuthenticationOptions{ServerCertificate=leaf},stop.Token);stream=ssl;}
    using(stream) {
     var bytes=new List<byte>();var one=new byte[1];
     while(bytes.Count<65536){if(await stream.ReadAsync(one,stop.Token)==0)return;bytes.Add(one[0]);int n=bytes.Count;if(n>=4&&bytes[n-4]==13&&bytes[n-3]==10&&bytes[n-2]==13&&bytes[n-1]==10)break;}
     var lines=Encoding.ASCII.GetString(bytes.ToArray()).Split("\r\n");var line=lines[0].Split(' ');var headers=new Dictionary<string,string>(StringComparer.OrdinalIgnoreCase);
     for(int i=1;i<lines.Length;i++){var p=lines[i].IndexOf(':');if(p>0)headers[lines[i][..p]]=lines[i][(p+1)..].Trim();}
     var length=headers.TryGetValue("Content-Length",out var l)?int.Parse(l):0;var body=new byte[length];var read=0;
     while(read<length){var n=await stream.ReadAsync(body.AsMemory(read),stop.Token);if(n==0)return;read+=n;}
     r=new IndependentRequest{Sequence=Count+1,Method=line[0],Target=line[1],Headers=headers,Body=Encoding.UTF8.GetString(body),ReceivedMs=clock.ElapsedMilliseconds};requests.Enqueue(r);
     if(!replies.TryDequeue(out var reply))reply=new IndependentReply{Status=500,Body="{\"error\":\"unscripted independent request\"}"};
     if(reply.Hold){while(await stream.ReadAsync(one,stop.Token)>0){} r.ClosedMs=clock.ElapsedMilliseconds;return;}
     var payload=Encoding.UTF8.GetBytes(reply.Body);var head=$"HTTP/1.1 {reply.Status} Fixture\r\nContent-Type: {reply.Media}\r\nContent-Length: {payload.Length}\r\nConnection: close\r\n";
     foreach(var h in reply.Headers)head+=$"{h.Key}: {h.Value}\r\n";
     await stream.WriteAsync(Encoding.ASCII.GetBytes(head+"\r\n"),stop.Token);await stream.WriteAsync(payload,stop.Token);
    }
   }catch(Exception e)when(e is IOException or OperationCanceledException or System.Security.Authentication.AuthenticationException or SocketException){if(r!=null)r.ClosedMs=clock.ElapsedMilliseconds;}
  }
 }
 public void Dispose(){stop.Cancel();listener.Stop();leaf?.Dispose();Root?.Dispose();}
}
