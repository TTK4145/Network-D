// build:  dmd main.d net/peers.d net/udp_bcast.d net/d-json/jsonx.d

import core.thread;
import core.time;
import std;


import peers;
import udp_bcast;





void main(string[] args){

    string id;
    args.getopt(
        "id", &id,
    );
    
    if(id == string.init){
        id = format!("%s#%d")(
            new TcpSocket(new InternetAddress("ntnu.no", 80))
                .localAddress
                .toAddrString,
            thisProcessID
        );
    }

    PeersConfig peersCfg    = {id: id};
    Tid         peerTx      = peers.init(peersCfg);
    BcastConfig bcastCfg    = {id: id, port: 16569};
    Tid         bcast       = udp_bcast.init!(HelloMsg, ArrayMsg)(bcastCfg);

    spawn(&helloFrom, id, bcast);


    while(true){
        receive(
            (HelloMsg a){
                writeln("Received HelloMsg: ", a);
            },
            (ArrayMsg a){
                writeln("Received ArrayMsg: ", a);
            },
            (PeerList a){
                writeln("Received peer list: ", a);
            }
        );
    }
}

void helloFrom(string id, Tid bcast){
    int iter;
    string msg = format!("Hello from %s!")(id);
    while(true){
        bcast.send(HelloMsg(msg, iter++));
        //bcast.send(ArrayMsg([1,2,3,4]));
        Thread.sleep(1.seconds);
    }

}




struct HelloMsg {
    string  str;
    int     iter;
}

// Special case for sending dynamic arrays ("pointer & length" arrays):
// Sending pointers between threads is not allowed unless they are explicitly shared, and modifying shared values is not allowed
//  Solution: duplicate and cast to shared before sending to udp_bcast.tx thread (for 2+ dimensions remember to deep copy!), 
//            cast away shared when reading freshly allocated value from udp_bcast.rx thread
struct ArrayMsg {
    shared int[] _arr;

    this(int[] a){
        this._arr = cast(shared)a.dup;
    }

    int[] arr(){
        return cast(int[])_arr;
    }
}