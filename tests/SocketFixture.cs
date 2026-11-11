using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Net;
using System.Net.Security;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Threading;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using System.Linq;

// Controlled HTTP/TLS fixture only. It never replaces an SDK handler or client.
public sealed class PsSocketRequest {
    public string Method {get;set;}
    public string Target {get;set;}
    public Dictionary<string,string> Headers {get;set;}
    public string Body {get;set;}
}
public sealed class PsSocketFixture : IDisposable {
    readonly TcpListener listener;
    readonly Thread worker;
    readonly X509Certificate2 certificate;
    volatile bool stopped;
    public volatile byte[] Body=Encoding.UTF8.GetBytes("{}");
    public volatile string Media="application/json";
    public volatile int Status=200;
    public volatile string ExtraHeaders="";
    public volatile PsExampleRoutes Routes;
    public ConcurrentQueue<PsSocketRequest> Requests=new();
    public ConcurrentQueue<string> Errors=new();
    public int Port=>((IPEndPoint)listener.LocalEndpoint).Port;
    public bool IsTls=>certificate!=null;
    public byte[] CertificateDer=>certificate.Export(X509ContentType.Cert);
    public PsSocketFixture(bool tls,bool cnOnly=false,bool wrongName=false){
        if(tls){
            using var rsa=RSA.Create(2048);
            var req=new CertificateRequest(wrongName?"CN=wrong.example.test":"CN=localhost",rsa,HashAlgorithmName.SHA256,RSASignaturePadding.Pkcs1);
            var san=new SubjectAlternativeNameBuilder();san.AddDnsName(wrongName?"wrong.example.test":"localhost");if(!wrongName)san.AddIpAddress(IPAddress.Loopback);
            if(!cnOnly)req.CertificateExtensions.Add(san.Build());
            req.CertificateExtensions.Add(new X509BasicConstraintsExtension(true,false,0,true));
            req.CertificateExtensions.Add(new X509KeyUsageExtension(X509KeyUsageFlags.DigitalSignature|X509KeyUsageFlags.KeyCertSign,true));
            certificate=req.CreateSelfSigned(DateTimeOffset.UtcNow.AddMinutes(-5),DateTimeOffset.UtcNow.AddDays(1));
        }
        listener=new TcpListener(IPAddress.Loopback,0);listener.Start();
        worker=new Thread(Serve){IsBackground=true};worker.Start();
    }
    public void Json(string value,int status=200){Body=Encoding.UTF8.GetBytes(value);Media="application/json";Status=status;ExtraHeaders="";}
    public void File(string media){
        Media=media;Status=200;ExtraHeaders="";
        Body=media switch {
            "application/pdf"=>Pdf(),
            "application/xml" or "text/xml"=>Encoding.UTF8.GetBytes("<?xml version=\"1.0\"?><synthetic/>"),
            "text/csv"=>Encoding.UTF8.GetBytes("a,b\n1,2\n"),
            _=>Zip(media=="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
        };
    }
    public static byte[] Pdf(bool unsupported=false, bool protectedFile=false){
        var text=new StringBuilder("%PDF-1.7\n");var offsets=new List<int>{0};
        string[] objects={"<< /Type /Catalog /Pages 2 0 R >>","<< /Type /Pages /Kids [3 0 R] /Count 1 >>","<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] /Resources << >> >>"};
        for(int i=0;i<objects.Length;i++){offsets.Add(Encoding.ASCII.GetByteCount(text.ToString()));text.Append($"{i+1} 0 obj\n{objects[i]}\nendobj\n");}
        int xref=Encoding.ASCII.GetByteCount(text.ToString());text.Append("xref\n0 4\n0000000000 65535 f \n");
        for(int i=1;i<offsets.Count;i++)text.Append(offsets[i].ToString("D10",System.Globalization.CultureInfo.InvariantCulture)+" 00000 n \n");
        text.Append("trailer\n<< /Size 4 /Root 1 0 R"+(unsupported?" /Prev 9":"")+(protectedFile?" /Encrypt << /Filter /Standard /V 1 /R 2 /P -4 /O (01234567890123456789012345678901) /U (01234567890123456789012345678901) >>":"")+" >>\nstartxref\n"+xref.ToString(System.Globalization.CultureInfo.InvariantCulture)+"\n%%EOF\n");
        return Encoding.ASCII.GetBytes(text.ToString());
    }
    // One actual worksheet part per worksheet. Repeated relationships are a
    // separate budget fixture with one actual sheet and only rId1 referenced.
    public static byte[] Spreadsheet(int count=1,bool duplicateNumericId=false,bool sharedPart=false,int relationshipCount=0){
        const string main="http://schemas.openxmlformats.org/spreadsheetml/2006/main",office="http://schemas.openxmlformats.org/officeDocument/2006/relationships",rel="http://schemas.openxmlformats.org/package/2006/relationships";
        var sheets=new StringBuilder();var relationships=new StringBuilder();var overrides=new StringBuilder();
        var parts=new Dictionary<string,string>();
        for(int i=1;i<=count;i++){
            string id=duplicateNumericId&&i==2?"01":i.ToString(System.Globalization.CultureInfo.InvariantCulture);
            sheets.Append($"<sheet name=\"Sheet{i}\" sheetId=\"{id}\" r:id=\"rId{i}\"/>");
        }
        int relationTotal=Math.Max(count,relationshipCount);int partTotal=sharedPart?1:count;
        for(int i=1;i<=relationTotal;i++)relationships.Append($"<Relationship Id=\"rId{i}\" Type=\"{office}/worksheet\" Target=\"worksheets/sheet{(sharedPart?1:Math.Min(i,count))}.xml\"/>");
        for(int i=1;i<=partTotal;i++){
            overrides.Append($"<Override PartName=\"/xl/worksheets/sheet{i}.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>");
            parts[$"xl/worksheets/sheet{i}.xml"]=$"<worksheet xmlns=\"{main}\"><sheetData/></worksheet>";
        }
        parts["[Content_Types].xml"]="<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/>"+overrides+"</Types>";
        parts["_rels/.rels"]=$"<Relationships xmlns=\"{rel}\"><Relationship Id=\"root\" Type=\"{office}/officeDocument\" Target=\"xl/workbook.xml\"/></Relationships>";
        parts["xl/workbook.xml"]=$"<workbook xmlns=\"{main}\" xmlns:r=\"{office}\"><sheets>{sheets}</sheets></workbook>";
        parts["xl/_rels/workbook.xml.rels"]=$"<Relationships xmlns=\"{rel}\">{relationships}</Relationships>";
        return ZipParts(parts);
    }
    public static byte[] ZipParts(Dictionary<string,string> parts){
        using var memory=new MemoryStream();
        using(var zip=new ZipArchive(memory,ZipArchiveMode.Create,true))foreach(var part in parts){using var writer=new StreamWriter(zip.CreateEntry(part.Key).Open());writer.Write(part.Value);}
        return memory.ToArray();
    }
    static byte[] Zip(bool sheet)=>sheet?Spreadsheet():ZipParts(new Dictionary<string,string>{{"synthetic.txt","synthetic"}});
    void Serve(){
        while(!stopped){
            try{
                using var client=listener.AcceptTcpClient();client.ReceiveTimeout=5000;client.SendTimeout=5000;
                Stream stream=client.GetStream();
                if(certificate!=null){var ssl=new SslStream(stream);ssl.AuthenticateAsServer(certificate);stream=ssl;}
                using(stream){
                    using var data=new MemoryStream();int b;
                    while((b=stream.ReadByte())!=-1){
                        data.WriteByte((byte)b);var bytes=data.GetBuffer();long n=data.Length;
                        if(n>=4&&bytes[n-4]==13&&bytes[n-3]==10&&bytes[n-2]==13&&bytes[n-1]==10)break;
                        if(n>32768)throw new IOException("Fixture header bound exceeded");
                    }
                    var lines=Encoding.ASCII.GetString(data.ToArray()).Split("\r\n");
                    var first=lines[0].Split(' ');var headers=new Dictionary<string,string>(StringComparer.OrdinalIgnoreCase);
                    foreach(var line in lines){var colon=line.IndexOf(':');if(colon>0)headers[line[..colon]]=line[(colon+1)..].Trim();}
                    var length=headers.TryGetValue("content-length",out var size)?int.Parse(size):0;
                    if(length>8*1024*1024)throw new IOException("Fixture body bound exceeded");
                    var body=new byte[length];stream.ReadExactly(body);
                    var request=new PsSocketRequest{Method=first[0],Target=first[1],Headers=headers,Body=Encoding.UTF8.GetString(body)};
                    Requests.Enqueue(request);
                    var payload=Body;var status=Status;var media=Media;var extra=ExtraHeaders;
                    if(Routes is {} routes){var reply=routes.Reply(request);status=reply.Status;media=reply.Media;payload=reply.Body;extra="";}
                    var response=Encoding.ASCII.GetBytes($"HTTP/1.1 {status} Synthetic\r\nContent-Type: {media}\r\nContent-Length: {payload.Length}\r\n{extra}Connection: close\r\n\r\n");
                    stream.Write(response);stream.Write(payload);stream.Flush();
                }
            }catch(Exception e){if(!stopped)Errors.Enqueue(e.GetType().Name+": "+e.Message);}
        }
    }
    public void Dispose(){stopped=true;listener.Stop();worker.Join(1000);certificate?.Dispose();}
}
// Route table for the homologation example: one synthetic reply per pinned operation route,
// document status moves from aprovado to cancelado only after a cancellation request.
public sealed class PsExampleRoutes {
    readonly List<(string Id,string Method,Regex Pattern)> routes=new();
    readonly Dictionary<string,string> responses=new(StringComparer.Ordinal);
    readonly ConcurrentDictionary<string,string> state=new(StringComparer.Ordinal);
    readonly string nfe,nfse;
    public volatile bool FailIssue;
    public volatile bool FailCancel;
    // Accepts each cancellation without the document ever showing "cancelado".
    public volatile bool StuckCancel;
    public PsExampleRoutes(string operationsJson,string fixturesJson,string nfeUuid,string nfseUuid){
        nfe=nfeUuid;nfse=nfseUuid;state["nfe"]="aprovado";state["nfse"]="aprovado";
        foreach(var op in JsonNode.Parse(operationsJson)!.AsArray()){
            var route=op!["route"]!.GetValue<string>();
            var pattern="^"+string.Join("/",route.Split('/').Select(x=>x.StartsWith("{")?"[^/]+":Regex.Escape(x)))+"$";
            routes.Add((op["id"]!.GetValue<string>(),op["method"]!.GetValue<string>(),new Regex(pattern)));
        }
        foreach(var f in JsonNode.Parse(fixturesJson)!.AsArray())responses[f!["id"]!.GetValue<string>()]=f["response"]!.ToJsonString();
    }
    public static string Payload(string fixturesJson,string id){
        var fixture=JsonNode.Parse(fixturesJson)!.AsArray().First(f=>f!["id"]!.GetValue<string>()==id)!;
        var body=JsonNode.Parse(fixture["input"]!["body"]!.ToJsonString())!.AsObject();body["ambiente"]=2;return body.ToJsonString();
    }
    string Document(string fixture,string uuid,string status){var node=JsonNode.Parse(responses[fixture])!.AsObject();node["uuid"]=uuid;node["status"]=status;return node.ToJsonString();}
    string Cancel(string model,string id){if(!StuckCancel)state[model]="cancelado";return responses[id];}
    public (int Status,string Media,byte[] Body) Reply(PsSocketRequest request){
        var path=request.Target.Split('?')[0];
        var matched=routes.Where(r=>r.Method==request.Method&&r.Pattern.IsMatch(path)).Select(r=>r.Id).ToArray();
        if(matched.Length!=1)return (404,"application/json",Encoding.UTF8.GetBytes("{}"));
        var id=matched[0];
        if(FailIssue&&id=="nfeIssueDocument")return (500,"application/json",Encoding.UTF8.GetBytes("{}"));
        if(FailCancel&&(id=="nfeCancelDocument"||id=="emitterCancelNfse"))return (500,"application/json",Encoding.UTF8.GetBytes("{}"));
        if(id.Contains("Pdf")||id.Contains("Danfe"))return (200,"application/pdf",PsSocketFixture.Pdf());
        if(id.Contains("Xml"))return (200,id=="fileGetNfseXml"?"text/xml":"application/xml",Encoding.UTF8.GetBytes("<?xml version=\"1.0\"?><synthetic/>"));
        var json=id switch{
            "nfeIssueDocument"=>Document("nfeGetDocument",nfe,"processando"),
            "nfeGetDocument"=>Document(id,nfe,state["nfe"]),
            "nfeCancelDocument"=>Cancel("nfe",id),
            "emitterIssueNfse"=>Document(id,nfse,"processando"),
            "emitterGetNfse"=>Document(id,nfse,state["nfse"]),
            "emitterCancelNfse"=>Cancel("nfse",id),
            _=>responses[id]
        };
        return (200,"application/json",Encoding.UTF8.GetBytes(json));
    }
}
