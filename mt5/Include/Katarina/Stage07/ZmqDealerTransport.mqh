#ifndef __KATARINA_STAGE07_ZMQ_DEALER_TRANSPORT_MQH__
#define __KATARINA_STAGE07_ZMQ_DEALER_TRANSPORT_MQH__

#include <Zmq/Zmq.mqh>
#include <Katarina/Stage07/Kat1Codec.mqh>

class CKatZmqDealerByteTransport
  {
private:
   Context *m_context;
   Socket  *m_socket;
   string   m_endpoint;
   string   m_identity;
   bool     m_started;
   ulong    m_frames_sent;
   ulong    m_frames_received;
   ulong    m_send_failures;
   ulong    m_receive_failures;

   bool IsLoopbackEndpoint(const string endpoint) const
     {
      return(StringFind(endpoint,"tcp://127.0.0.1:")==0 ||
             StringFind(endpoint,"tcp://localhost:")==0 ||
             StringFind(endpoint,"tcp://[::1]:")==0);
     }

public:
                     CKatZmqDealerByteTransport(void)
     {
      m_context=NULL;
      m_socket=NULL;
      m_endpoint="";
      m_identity="";
      m_started=false;
      m_frames_sent=0;
      m_frames_received=0;
      m_send_failures=0;
      m_receive_failures=0;
     }

                    ~CKatZmqDealerByteTransport(void)
     {
      Stop();
     }

   bool              Start(const string endpoint,
                           const string identity,
                           const int send_hwm=256,
                           const int receive_hwm=256)
     {
      if(m_started)
         return(true);

      if(!MQLInfoInteger(MQL_DLLS_ALLOWED))
         return(false);

      if(!IsLoopbackEndpoint(endpoint) ||
         identity=="" ||
         send_hwm<=0 ||
         receive_hwm<=0)
         return(false);

      m_context=new Context("__katarina_stage07_shared_zmq_context__");
      if(CheckPointer(m_context)!=POINTER_DYNAMIC)
        {
         m_context=NULL;
         return(false);
        }

      m_socket=new Socket(*m_context,ZMQ_DEALER);
      if(CheckPointer(m_socket)!=POINTER_DYNAMIC || !m_socket.valid())
        {
         if(CheckPointer(m_socket)==POINTER_DYNAMIC)
            delete m_socket;
         m_socket=NULL;
         delete m_context;
         m_context=NULL;
         return(false);
        }

      bool configured=true;
      configured=(m_socket.setLinger(0) && configured);
      configured=(m_socket.setSendHighWaterMark(send_hwm) && configured);
      configured=(m_socket.setReceiveHighWaterMark(receive_hwm) && configured);
      configured=(m_socket.setImmediate(true) && configured);
      configured=(m_socket.setReconnectInterval(100) && configured);
      configured=(m_socket.setReconnectIntervalMax(1000) && configured);
      configured=(m_socket.setIdentity(identity) && configured);

      if(!configured || !m_socket.connect(endpoint))
        {
         delete m_socket;
         m_socket=NULL;
         delete m_context;
         m_context=NULL;
         return(false);
        }

      m_endpoint=endpoint;
      m_identity=identity;
      m_started=true;
      return(true);
     }

   void              Stop(void)
     {
      m_started=false;

      if(CheckPointer(m_socket)==POINTER_DYNAMIC)
        {
         if(m_endpoint!="")
            m_socket.disconnect(m_endpoint);
         delete m_socket;
        }
      m_socket=NULL;

      if(CheckPointer(m_context)==POINTER_DYNAMIC)
         delete m_context;
      m_context=NULL;

      m_endpoint="";
      m_identity="";
     }

   bool              Started(void) const
     {
      return(m_started &&
             CheckPointer(m_socket)==POINTER_DYNAMIC &&
             m_socket.valid());
     }

   bool              SendFrame(const uchar &frame[])
     {
      if(!Started() || ArraySize(frame)<=0)
        {
         m_send_failures++;
         return(false);
        }

      SKat1Header header;
      string error="";
      if(!Kat1ValidateFrame(frame,header,error))
        {
         m_send_failures++;
         return(false);
        }

      if(!m_socket.send(frame,true))
        {
         m_send_failures++;
         return(false);
        }

      m_frames_sent++;
      return(true);
     }

   bool              ReceiveFrame(uchar &frame[])
     {
      ArrayResize(frame,0);
      if(!Started())
        {
         m_receive_failures++;
         return(false);
        }

      ZmqMsg message;
      if(!m_socket.recv(message,true))
         return(false);

      message.getData(frame);
      if(ArraySize(frame)<=0)
        {
         m_receive_failures++;
         ArrayResize(frame,0);
         return(false);
        }

      SKat1Header header;
      string error="";
      if(!Kat1ValidateFrame(frame,header,error))
        {
         m_receive_failures++;
         ArrayResize(frame,0);
         return(false);
        }

      m_frames_received++;
      return(true);
     }

   ulong             FramesSent(void) const
     {
      return(m_frames_sent);
     }

   ulong             FramesReceived(void) const
     {
      return(m_frames_received);
     }

   ulong             SendFailures(void) const
     {
      return(m_send_failures);
     }

   ulong             ReceiveFailures(void) const
     {
      return(m_receive_failures);
     }

   string            Endpoint(void) const
     {
      return(m_endpoint);
     }

   string            Identity(void) const
     {
      return(m_identity);
     }
  };

#endif
