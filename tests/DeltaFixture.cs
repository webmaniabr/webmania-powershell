using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

// Author-owned wire peers only. SDK calls remain public exported PowerShell commands.
public sealed class DeltaRequest {
    public string Method {get;set;}=""; public string Target {get;set;}=""; public string Body {get;set;}="";
    public Dictionary<string,string> Headers {get;set;}=new(StringComparer.OrdinalIgnoreCase);
}
public sealed class DeltaRawServer:IDisposable {
    readonly TcpListener listener; readonly CancellationTokenSource stop=new();
    public readonly ConcurrentQueue<byte[]> Replies=new(); public readonly ConcurrentQueue<DeltaRequest> Requests=new();
    public readonly ConcurrentQueue<string> Errors=new();
    public int Port=>((IPEndPoint)listener.LocalEndpoint).Port;public int Count=>Requests.Count;public int Accepts;
    public DeltaRawServer(bool ipv6=false){listener=new(ipv6?IPAddress.IPv6Loopback:IPAddress.Loopback,0);listener.Start();_=Task.Run(async()=>{while(!stop.IsCancellationRequested)try{var c=await listener.AcceptTcpClientAsync(stop.Token);Interlocked.Increment(ref Accepts);_=Task.Run(()=>Handle(c));}catch(OperationCanceledException){break;}});}
    public void Enqueue(string raw)=>Replies.Enqueue(Encoding.UTF8.GetBytes(raw));
    public void Json(string body,int status=200,string headers="")=>Reply(Encoding.UTF8.GetBytes(body),"application/json",status,headers);
    public void Reply(byte[] body,string media,int status=200,string headers=""){
        var head=Encoding.ASCII.GetBytes($"HTTP/1.1 {status} Fixture\r\nContent-Type: {media}\r\nContent-Length: {body.Length}\r\nConnection: close\r\n{headers}\r\n");
        Replies.Enqueue(head.Concat(body).ToArray());
    }
    async Task Handle(TcpClient client){using(client)try{var stream=client.GetStream();var data=new List<byte>();var one=new byte[1];
        while(data.Count<65536){if(await stream.ReadAsync(one,stop.Token)==0)return;data.Add(one[0]);int n=data.Count;if(n>=4&&data[n-4]==13&&data[n-3]==10&&data[n-2]==13&&data[n-1]==10)break;}
        var lines=Encoding.ASCII.GetString(data.ToArray()).Split("\r\n");var first=lines[0].Split(' ');var headers=new Dictionary<string,string>(StringComparer.OrdinalIgnoreCase);
        foreach(var line in lines.Skip(1)){int i=line.IndexOf(':');if(i>0)headers[line[..i]]=line[(i+1)..].Trim();}
        int length=headers.TryGetValue("Content-Length",out var size)?int.Parse(size):0;if(length>8*1024*1024)throw new IOException();var body=new byte[length];await stream.ReadExactlyAsync(body,stop.Token);
        Requests.Enqueue(new DeltaRequest{Method=first[0],Target=first[1],Headers=headers,Body=Encoding.UTF8.GetString(body)});
        if(!Replies.TryDequeue(out var reply))throw new IOException("Unscripted request");await stream.WriteAsync(reply,stop.Token);
    }catch(Exception e)when(e is IOException or SocketException or OperationCanceledException){if(!stop.IsCancellationRequested)Errors.Enqueue(e.GetType().Name);}}
    public void Dispose(){stop.Cancel();listener.Stop();}
}
public sealed class DeltaHandshakePeer:IDisposable {
    readonly TcpListener listener=new(IPAddress.Loopback,0);readonly CancellationTokenSource stop=new();
    public int Port=>((IPEndPoint)listener.LocalEndpoint).Port; public int Bytes;public bool Closed;public int Accepts;
    public DeltaHandshakePeer(){listener.Start();_=Task.Run(async()=>{try{using var c=await listener.AcceptTcpClientAsync(stop.Token);Interlocked.Increment(ref Accepts);var stream=c.GetStream();var bytes=new byte[8192];while(true){int count=await stream.ReadAsync(bytes,stop.Token);if(count==0){Closed=true;break;}Interlocked.Add(ref Bytes,count);}}catch(Exception e)when(e is IOException or OperationCanceledException or SocketException){Closed=true;}});}
    public void Dispose(){stop.Cancel();listener.Stop();}
}
public sealed class DeltaDnsQuery {public string Host {get;set;}="";public int Type {get;set;}public long Milliseconds {get;set;}}
public sealed class DeltaDnsPeer:IDisposable {
    readonly UdpClient udp=new(new IPEndPoint(IPAddress.Loopback,53));readonly CancellationTokenSource stop=new();readonly Stopwatch watch=Stopwatch.StartNew();
    public readonly ConcurrentQueue<DeltaDnsQuery> Queries=new(); public long Milliseconds=>watch.ElapsedMilliseconds;
    public DeltaDnsPeer(){_=Task.Run(async()=>{while(!stop.IsCancellationRequested)try{var q=await udp.ReceiveAsync(stop.Token);var b=q.Buffer;int i=12;var labels=new List<string>();while(i<b.Length&&b[i]!=0){int n=b[i++];labels.Add(Encoding.ASCII.GetString(b,i,n));i+=n;}i++;int type=(b[i]<<8)|b[i+1];string host=string.Join('.',labels);Queries.Enqueue(new(){Host=host,Type=type,Milliseconds=watch.ElapsedMilliseconds});if(host.StartsWith("blocked",StringComparison.Ordinal))continue;
        int end=i+4;var response=b[..end].ToList();response[2]=0x81;response[3]=0x80;response[6]=0;response[7]=(byte)(type==1?1:0);response[8]=response[9]=response[10]=response[11]=0;if(type==1)response.AddRange(new byte[]{0xc0,0x0c,0,1,0,1,0,0,0,0,0,4,127,0,0,1});await udp.SendAsync(response.ToArray(),q.RemoteEndPoint,stop.Token);
    }catch(OperationCanceledException){}catch(ObjectDisposedException)when(stop.IsCancellationRequested){} });}
    public void Dispose(){stop.Cancel();udp.Dispose();}
}
public sealed class DeltaBacklog:IDisposable {
    readonly Socket listener=new(AddressFamily.InterNetwork,SocketType.Stream,ProtocolType.Tcp);
    readonly Socket first=new(AddressFamily.InterNetwork,SocketType.Stream,ProtocolType.Tcp),second=new(AddressFamily.InterNetwork,SocketType.Stream,ProtocolType.Tcp);
    public int Port=>((IPEndPoint)listener.LocalEndPoint).Port;
    public DeltaBacklog(){listener.Bind(new IPEndPoint(IPAddress.Loopback,0));listener.Listen(1);first.Connect(IPAddress.Loopback,Port);second.Connect(IPAddress.Loopback,Port);}
    public int SynSent=>new[]{"/proc/net/tcp","/proc/net/tcp6"}.Sum(path=>File.ReadAllLines(path).Skip(1).Count(line=>{var f=line.Split((char[])null,StringSplitOptions.RemoveEmptyEntries);return f[2].EndsWith(":"+Port.ToString("X4"),StringComparison.Ordinal)&&f[3]=="02";}));
    public void Dispose(){first.Dispose();second.Dispose();listener.Dispose();}
}

public static class DeltaArchives {
 public static byte[] Stored(string[] names){using var memory=new MemoryStream();using(var zip=new System.IO.Compression.ZipArchive(memory,System.IO.Compression.ZipArchiveMode.Create,true))foreach(string name in names){var entry=zip.CreateEntry(name,System.IO.Compression.CompressionLevel.NoCompression);using var stream=entry.Open();stream.Write(Encoding.ASCII.GetBytes("synthetic archive payload"));}return memory.ToArray();}
 public static int Signature(byte[] data,uint signature,int start=0){for(int i=start;i<=data.Length-4;i++)if(BitConverter.ToUInt32(data,i)==signature)return i;return -1;}
 public static byte[] Change(byte[] original,int offset,byte value){var copy=(byte[])original.Clone();copy[offset]=value;return copy;}
}
