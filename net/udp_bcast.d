import std.array;
import std.algorithm;
import std.concurrency;
import std.conv;
import std.file;
import std.getopt;
import std.meta;
import std.socket;
import std.stdio;
import std.string;
import std.traits;
import std.typecons;

import jsonx;


template isSerialisable(T){
    enum isSerialisable = is(T == struct)  &&  (allSatisfy!(isBuiltinType, RepresentationTypeTuple!T) && !hasUnsharedAliasing!T);
}

struct BcastConfig {
    ushort              port;
    size_t              bufSize = 1024;
    string              id;
    immutable string[]  ignoreList;
}

Tid init(T...)(BcastConfig cfg, Tid receiver = thisTid) if(allSatisfy!(isSerialisable, T)){
    spawn(&rx!T, cfg, receiver);
    return spawn(&tx!T, cfg);
}

struct Msg {
    string id;
    string type;
    string json;
}

private void rx(T...)(BcastConfig cfg, Tid receiver){

    scope(exit) writeln(__FUNCTION__, " died");
    try {

    auto    addr    = new InternetAddress(cfg.port);
    auto    sock    = new UdpSocket();
    ubyte[] buf     = new ubyte[](cfg.bufSize);
    Address remote  = new UnknownAddress;

    sock.setOption(SocketOptionLevel.SOCKET, SocketOption.BROADCAST, 1);
    sock.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, 1);
    sock.bind(addr);
    
    while(true){
        
        auto n = sock.receiveFrom(buf, remote);
        if(n > 0){
            string s = cast(string)buf[0..n];
            Msg m;
            try {
                m = s.jsonDecode!Msg;
            } catch(Exception e){
                // garbled message that cannot be decoded -> ignore
            }
            if(cfg.ignoreList.canFind(m.id)){
                continue;
            }
            foreach(t; T){
                if(fullyQualifiedName!t == m.type){
                    try {
                        receiver.send(m.json.jsonDecode!t);
                    } catch(Exception e){
                        writeln(__FUNCTION__, " Decoding type ", t.stringof, " failed: ", e.msg);
                    }
                }
            }
        }
        buf[0..n] = 0;
    }
    
    } catch(Throwable t){ t.writeln; throw t; }

}

private void tx(T...)(BcastConfig cfg){
    scope(exit) writeln(__FUNCTION__, " died");
    try {
    
    auto addr = new InternetAddress("255.255.255.255", cfg.port);
    auto sock = new UdpSocket();

    sock.setOption(SocketOptionLevel.SOCKET, SocketOption.BROADCAST, 1);
    sock.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, 1);

        
    while(true){
        receive(
            (Variant v){
                foreach(t; T){
                    if(v.type == typeid(t)){
                        Msg msg = {
                            id:     cfg.id,
                            type:   fullyQualifiedName!t,
                            json:   v.get!t.jsonEncode,
                        };
                        sock.sendTo(msg.jsonEncode, addr);
                        return;
                    }
                }
                writeln(__FUNCTION__, " Unexpected type! ", v);
            }
        );
    }
    } catch(Throwable t){ t.writeln; throw t; }    
}








