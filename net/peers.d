import  core.thread,
        std.algorithm,
        std.array,
        std.concurrency,
        std.conv,
        std.datetime,
        std.file,
        std.getopt,
        std.socket,
        std.stdio;


private __gshared ushort        port            = 16567;
private __gshared int           timeout_ms      = 350;
private __gshared Duration      timeout;        
private __gshared int           interval_ms     = 100;
private __gshared Duration      interval;       
private __gshared string        id_str          = "default";
private __gshared ubyte         _id;

ubyte id(){
    return _id;
}


struct PeerList {
    immutable(ubyte)[] peers;
    alias peers this;
}

struct TxEnable {
    bool enable;
    alias enable this;
}

Tid init(Tid receiver = thisTid){

    string[] configContents;
    try {
        configContents = readText("net.con").split;
        getopt( configContents,
            std.getopt.config.passThrough,
            "net_peer_port",        &port,
            "net_peer_timeout",     &timeout_ms,
            "net_peer_interval",    &interval_ms,
            "net_peer_id",          &id_str
        );
        
            
        timeout = timeout_ms.msecs;
        interval = interval_ms.msecs;
        
        if(id_str == "default"){ 
            _id = new TcpSocket(new InternetAddress("google.com", 80))
                .localAddress
                .toAddrString
                .splitter('.')
                .array[$-1]
                .to!ubyte;
        } else {
            _id = id_str.to!ubyte;
        }
        
    } catch(Exception e){
        writeln("Unable to load net_peer config:\n", e.msg);
    }

    
    spawn(&rx, receiver);
    return spawn(&tx);
}



private void tx(){
    scope(exit) writeln(__FUNCTION__, " died");
    try {

    auto    addr                    = new InternetAddress("255.255.255.255", port);
    auto    sock                    = new UdpSocket();
    ubyte[1] buf                    = [id];

    sock.setOption(SocketOptionLevel.SOCKET, SocketOption.BROADCAST, 1);
    sock.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, 1);

    bool txEnable = true;
    while(true){
        receiveTimeout(interval, 
            (TxEnable t){
                txEnable = t;
            }
        );
        if(txEnable){
            sock.sendTo(buf, addr);
        }
    }
    } catch(Throwable t){ t.writeln; throw t; }
}

private void rx(Tid receiver){
    scope(exit) writeln(__FUNCTION__, " died");
    try {

    auto    addr                    = new InternetAddress(port);
    auto    sock                    = new UdpSocket();

    ubyte[1]        buf;
    SysTime[ubyte]  lastSeen;
    bool            listHasChanges;


    sock.setOption(SocketOptionLevel.SOCKET, SocketOption.BROADCAST, 1);
    sock.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, 1);
    sock.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, timeout);
    sock.bind(addr);

    while(true){
        listHasChanges  = false;
        buf[]           = 0;

        sock.receiveFrom(buf);

        if(buf[0] != 0){
            if(buf[0] !in lastSeen){
                listHasChanges = true;
            }
            lastSeen[buf[0]] = Clock.currTime;
        }

        foreach(k, v; lastSeen){
            if(Clock.currTime - v > timeout){
                listHasChanges = true;
                lastSeen.remove(k);
            }
        }

        if(listHasChanges){
            ownerTid.send(PeerList(lastSeen.keys.idup));
        }
    }
    } catch(Throwable t){ t.writeln; throw t; }
}