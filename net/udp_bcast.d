import  std.array,
        std.algorithm,
        std.concurrency,
        std.conv,
        std.file,
        std.getopt,
        std.meta,
        std.socket,
        std.stdio,
        std.string,
        std.traits,
        std.typecons;

import jsonx;


private __gshared ushort        port            = 16568;
private __gshared size_t        bufSize         = 1024;
private __gshared int           recvFromSelf    = 0;


template isSerialisable(T){
    enum isSerialisable = is(T == struct)  &&  (allSatisfy!(isBuiltinType, RepresentationTypeTuple!T) && !hasUnsharedAliasing!T);
}


Tid init(T...)(ubyte id, Tid receiver = thisTid) if(allSatisfy!(isSerialisable, T)){
    string[] configContents;
    try {
        configContents = readText("net.con").split;
        getopt( configContents,
            std.getopt.config.passThrough,
            "net_bcast_port",           &port,
            "net_bcast_bufsize",        &bufSize,
            "net_bcast_recvFromSelf",   &recvFromSelf,
        );        
    } catch(Exception e){
        writeln("Unable to load net_bcast config:\n", e.msg);
    }

    spawn(&rx!T, id, receiver);
    return spawn(&tx!T, id);
}


private void rx(T...)(ubyte id, Tid receiver){

    scope(exit) writeln(__FUNCTION__, " died");
    try {

    auto    addr    = new InternetAddress(port);
    auto    sock    = new UdpSocket();
    ubyte[] buf     = new ubyte[](bufSize);
    Address remote  = new UnknownAddress;

    sock.setOption(SocketOptionLevel.SOCKET, SocketOption.BROADCAST, 1);
    sock.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, 1);
    sock.bind(addr);
    
    while(true){
        
        auto n = sock.receiveFrom(buf, remote);
        if(n > 0){
            ubyte remoteId = buf[0];
            if(recvFromSelf  ||  remoteId != id){
                string s = (cast(string)buf[1..n].dup).strip('\0');
                foreach(t; T){
                    if(s.startsWith(t.stringof ~ "{")){
                        s.skipOver(t.stringof);
                        try {
                            receiver.send(s.jsonDecode!t);
                        } catch(Exception e){
                            writeln(__FUNCTION__, " Decoding type ", t.stringof, " failed: ", e.msg);
                        }
                    }
                }
            }
        }
        buf[0..n] = 0;
    }
    
    } catch(Throwable t){ t.writeln; throw t; }

}

private void tx(T...)(ubyte id){
    scope(exit) writeln(__FUNCTION__, " died");
    try {
    
    auto    addr    = new InternetAddress("255.255.255.255", port);
    auto    sock    = new UdpSocket();

    sock.setOption(SocketOptionLevel.SOCKET, SocketOption.BROADCAST, 1);
    sock.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, 1);

        
    while(true){
        receive(
            (Variant v){
                foreach(t; T){
                    if(v.type == typeid(t)){
                        string msg = __traits(identifier, t) ~ v.get!t.jsonEncode;
                        sock.sendTo([id] ~ cast(ubyte[])msg, addr);
                        return;
                    }
                }
                writeln(__FUNCTION__, " Unexpected type! ", v);
            }
        );
    }
    } catch(Throwable t){ t.writeln; throw t; }    
}








