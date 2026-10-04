#ifndef __KATARINA_STAGE07_NATIVE_TCP_TRANSPORT_MQH__
#define __KATARINA_STAGE07_NATIVE_TCP_TRANSPORT_MQH__

#include <Katarina/Stage07/Kat1Codec.mqh>

class CKatNativeTcpByteTransport
  {
private:
   int    m_socket;
   string m_endpoint;
   string m_host;
   uint   m_port;
   uint   m_io_timeout_ms;
   bool   m_started;
   ulong  m_frames_sent;
   ulong  m_frames_received;
   ulong  m_send_failures;
   ulong  m_receive_failures;

   bool ParseEndpoint(const string endpoint,string &host,uint &port) const
     {
      host="";
      port=0;
      if(StringFind(endpoint,"tcp://")!=0)
         return(false);

      const string rest=StringSubstr(endpoint,6);
      const int colon=StringFind(rest,":");
      if(colon<=0)
         return(false);

      host=StringSubstr(rest,0,colon);
      if(host!="127.0.0.1" && host!="localhost")
         return(false);

      const string port_text=StringSubstr(rest,colon+1);
      if(port_text=="")
         return(false);

      const long parsed=StringToInteger(port_text);
      if(parsed<=0 || parsed>65535)
         return(false);

      port=(uint)parsed;
      return(true);
     }

   bool ReadExact(uchar &target[],
                  const int target_offset,
                  const int count,
                  const uint timeout_ms)
     {
      if(count<0 || target_offset<0 ||
         target_offset+count>ArraySize(target))
         return(false);

      int done=0;
      const ulong deadline=GetTickCount64()+(ulong)timeout_ms;

      while(done<count)
        {
         if(m_socket==INVALID_HANDLE || !SocketIsConnected(m_socket))
            return(false);

         const uint available=SocketIsReadable(m_socket);
         if(available==0)
           {
            if(GetTickCount64()>=deadline)
               return(false);
            Sleep(1);
            continue;
           }

         int want=count-done;
         if((uint)want>available)
            want=(int)available;
         if(want<=0)
            continue;

         uchar chunk[];
         ArrayResize(chunk,want);
         const ulong now=GetTickCount64();
         uint remaining=1;
         if(deadline>now)
           {
            const ulong delta=deadline-now;
            remaining=(uint)(delta>1000 ? 1000 : delta);
            if(remaining==0)
               remaining=1;
           }

         const int got=SocketRead(m_socket,chunk,(uint)want,remaining);
         if(got<0)
            return(false);
         if(got==0)
           {
            if(GetTickCount64()>=deadline)
               return(false);
            continue;
           }

         ArrayCopy(target,chunk,target_offset+done,0,got);
         done+=got;
        }

      return(true);
     }

public:
                     CKatNativeTcpByteTransport(void)
     {
      m_socket=INVALID_HANDLE;
      m_endpoint="";
      m_host="";
      m_port=0;
      m_io_timeout_ms=5000;
      m_started=false;
      m_frames_sent=0;
      m_frames_received=0;
      m_send_failures=0;
      m_receive_failures=0;
     }

                    ~CKatNativeTcpByteTransport(void)
     {
      Stop();
     }

   bool              Start(const string endpoint,
                           const uint connect_timeout_ms=3000,
                           const uint io_timeout_ms=5000)
     {
      if(m_started)
         return(true);
      if(connect_timeout_ms==0 || io_timeout_ms==0)
         return(false);

      string host="";
      uint port=0;
      if(!ParseEndpoint(endpoint,host,port))
         return(false);

      ResetLastError();
      const int socket=SocketCreate(SOCKET_DEFAULT);
      if(socket==INVALID_HANDLE)
         return(false);

      if(!SocketTimeouts(socket,io_timeout_ms,io_timeout_ms))
        {
         SocketClose(socket);
         return(false);
        }

      if(!SocketConnect(socket,host,port,connect_timeout_ms))
        {
         SocketClose(socket);
         return(false);
        }

      m_socket=socket;
      m_endpoint=endpoint;
      m_host=host;
      m_port=port;
      m_io_timeout_ms=io_timeout_ms;
      m_started=true;
      return(true);
     }

   void              Stop(void)
     {
      if(m_socket!=INVALID_HANDLE)
         SocketClose(m_socket);
      m_socket=INVALID_HANDLE;
      m_endpoint="";
      m_host="";
      m_port=0;
      m_started=false;
     }

   bool              Started(void) const
     {
      return(m_started &&
             m_socket!=INVALID_HANDLE &&
             SocketIsConnected(m_socket));
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

      const int total=ArraySize(frame);
      int offset=0;
      while(offset<total)
        {
         if(!SocketIsWritable(m_socket))
           {
            m_send_failures++;
            return(false);
           }

         const int remaining=total-offset;
         uchar chunk[];
         ArrayResize(chunk,remaining);
         ArrayCopy(chunk,frame,0,offset,remaining);

         const int sent=SocketSend(m_socket,chunk,(uint)remaining);
         if(sent<=0)
           {
            m_send_failures++;
            return(false);
           }
         offset+=sent;
        }

      m_frames_sent++;
      return(true);
     }

   bool              ReceiveFrame(uchar &frame[],
                                  const uint timeout_ms=0)
     {
      ArrayResize(frame,0);
      if(!Started())
        {
         m_receive_failures++;
         return(false);
        }

      const uint effective_timeout=(timeout_ms>0 ? timeout_ms : m_io_timeout_ms);
      uchar header_bytes[];
      ArrayResize(header_bytes,KAT1_HEADER_BYTES);
      if(!ReadExact(header_bytes,0,KAT1_HEADER_BYTES,effective_timeout))
        {
         m_receive_failures++;
         return(false);
        }

      if(header_bytes[0]!=0x4B ||
         header_bytes[1]!=0x41 ||
         header_bytes[2]!=0x54 ||
         header_bytes[3]!=0x31 ||
         Kat1ReadU16LE(header_bytes,6)!=KAT1_HEADER_BYTES)
        {
         m_receive_failures++;
         return(false);
        }

      const uint frame_length=Kat1ReadU32LE(header_bytes,16);
      if(frame_length<KAT1_HEADER_BYTES || frame_length>KAT1_MAX_FRAME_BYTES)
        {
         m_receive_failures++;
         return(false);
        }

      ArrayResize(frame,(int)frame_length);
      ArrayCopy(frame,header_bytes,0,0,KAT1_HEADER_BYTES);

      const int remaining=(int)frame_length-KAT1_HEADER_BYTES;
      if(remaining>0 &&
         !ReadExact(frame,KAT1_HEADER_BYTES,remaining,effective_timeout))
        {
         m_receive_failures++;
         ArrayResize(frame,0);
         return(false);
        }

      SKat1Header decoded;
      string error="";
      if(!Kat1ValidateFrame(frame,decoded,error))
        {
         m_receive_failures++;
         ArrayResize(frame,0);
         return(false);
        }

      m_frames_received++;
      return(true);
     }

   ulong             FramesSent(void) const { return(m_frames_sent); }
   ulong             FramesReceived(void) const { return(m_frames_received); }
   ulong             SendFailures(void) const { return(m_send_failures); }
   ulong             ReceiveFailures(void) const { return(m_receive_failures); }
   string            Endpoint(void) const { return(m_endpoint); }
   string            Host(void) const { return(m_host); }
   uint              Port(void) const { return(m_port); }
  };

#endif
