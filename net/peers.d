import core.thread;
import std.algorithm;
import std.array;
import std.concurrency;
import std.conv;
import std.datetime;
import std.file;
import std.format;
import std.getopt;
import std.process;
import std.socket;
import std.stdio;



struct PeersConfig {
    ushort  port        = 16567;
    int     timeout_ms  = 105;
    int     interval_ms = 10;
    string  id          = "";
}

struct PeerList {
    immutable string[] peers;
    alias peers this;
}

struct TxEnable {
    bool enable;
    alias enable this;
}

Tid init(PeersConfig cfg, Tid receiver = thisTid){
    spawn(&rx, cfg, receiver);
    return spawn(&tx, cfg);
}



private void tx(PeersConfig cfg){
    scope(exit) writeln(__FUNCTION__, " died");
    try {

    auto addr = new InternetAddress("255.255.255.255", cfg.port);
    auto sock = new UdpSocket();

    sock.setOption(SocketOptionLevel.SOCKET, SocketOption.BROADCAST, 1);
    sock.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, 1);

    Duration interval = cfg.interval_ms.msecs;
    bool txEnable = true;
    while(true){
        receiveTimeout(interval, 
            (TxEnable t){
                txEnable = t;
            }
        );
        if(txEnable){
            sock.sendTo(cfg.id, addr);
        }
    }
    } catch(Throwable t){ t.writeln; throw t; }
}

private void rx(PeersConfig cfg, Tid receiver){
    scope(exit) writeln(__FUNCTION__, " died");
    try {

    auto addr = new InternetAddress(cfg.port);
    auto sock = new UdpSocket();

    ubyte[256]          buf;
    SysTime[string]     lastSeen;
    bool                listHasChanges;

    Duration timeout = cfg.timeout_ms.msecs;
    sock.setOption(SocketOptionLevel.SOCKET, SocketOption.BROADCAST, 1);
    sock.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, 1);
    sock.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, timeout);
    sock.bind(addr);

    while(true){
        listHasChanges  = false;
        buf[]           = 0;

        auto n = sock.receiveFrom(buf);

        if(buf[0] != 0){
            string remoteID = cast(string)buf[0..n].dup;
            if(remoteID !in lastSeen){
                listHasChanges = true;
            }
            lastSeen[remoteID] = Clock.currTime;
        }

        foreach(k, v; lastSeen){
            if(Clock.currTime - v > timeout){
                listHasChanges = true;
                lastSeen.remove(k);
            }
        }

        if(listHasChanges){
            receiver.send(PeerList(lastSeen.keys.map!(a => a.idup).array.idup));
        }
    }
    } catch(Throwable t){ t.writeln; throw t; }
}
