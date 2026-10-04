#ifndef __KATARINA_STAGE07_BRIDGE_TRANSPORT_MQH__
#define __KATARINA_STAGE07_BRIDGE_TRANSPORT_MQH__

#include <Katarina/TransportPort.mqh>
#include <Katarina/NativeFacts.mqh>
#include <Katarina/Stage07/ZmqDealerTransport.mqh>
#include <Katarina/Stage07/Kat1SystemMessages.mqh>
#include <Katarina/Stage07/IdentityV1.mqh>
#include <Katarina/Stage07/WireSequence.mqh>

#define KAT7_TRANSPORT_STOPPED          0
#define KAT7_TRANSPORT_WAITING_HELLO    1
#define KAT7_TRANSPORT_RECOVERING       2
#define KAT7_TRANSPORT_FAULTED          3
#define KAT7_TRANSPORT_ACK_PENDING       4

#define KAT7_HEARTBEAT_INTERVAL_MS 1000
#define KAT7_EA_BUILD_VERSION 700

class CKatStage07Transport : public CKatTransportPort
  {
private:
   CKatZmqDealerByteTransport m_wire;
   CKatWireSequence           m_sequence;

   string m_endpoint;
   ulong  m_stream_id;
   ulong  m_boot_id;
   ulong  m_broker_login;
   string m_broker_server;
   string m_account_currency;
   int    m_currency_digits;
   ENUM_ACCOUNT_MARGIN_MODE m_margin_mode;
   ENUM_ACCOUNT_TRADE_MODE  m_trade_mode;

   int    m_state;
   ulong  m_last_heartbeat_ms;
   ulong  m_latest_consumed_command_sequence;
   ulong  m_latest_inbound_sequence;
   bool   m_configured;
   uchar  m_pending_control[];
   ushort m_pending_message_type;

   bool HasPendingControl(void) const
     {
      return(ArraySize(m_pending_control)>0);
     }

   void ClearPendingControl(void)
     {
      ArrayResize(m_pending_control,0);
      m_pending_message_type=0;
     }

   bool QueuePendingControl(const uchar &frame[],
                            const ushort message_type)
     {
      if(HasPendingControl())
         return(false);

      const int size=ArraySize(frame);
      if(size<=0)
         return(false);

      if(ArrayResize(m_pending_control,size)!=size)
         return(false);

      for(int i=0;i<size;i++)
         m_pending_control[i]=frame[i];

      m_pending_message_type=message_type;
      return(true);
     }

   bool FlushPendingControl(void)
     {
      if(!HasPendingControl())
         return(true);

      if(!m_wire.SendFrame(m_pending_control))
         return(false);

      const ushort sent_type=m_pending_message_type;
      ClearPendingControl();

      if(sent_type==KAT1_MSG_HEARTBEAT)
         m_last_heartbeat_ms=GetTickCount64();
      else if(sent_type==KAT1_MSG_HELLO_ACK)
         m_state=KAT7_TRANSPORT_RECOVERING;

      return(true);
     }

   uchar NormalizeAccountMode(void) const
     {
      if(m_margin_mode==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
         return(1);
      if(m_margin_mode==ACCOUNT_MARGIN_MODE_RETAIL_NETTING)
         return(2);
      if(m_margin_mode==ACCOUNT_MARGIN_MODE_EXCHANGE)
         return(3);
      return(0);
     }

   uchar NormalizeTradeMode(void) const
     {
      if(m_trade_mode==ACCOUNT_TRADE_MODE_DEMO)
         return(1);
      if(m_trade_mode==ACCOUNT_TRADE_MODE_CONTEST)
         return(2);
      if(m_trade_mode==ACCOUNT_TRADE_MODE_REAL)
         return(3);
      return(0);
     }

   ulong SourceTimeNs(void) const
     {
      datetime value=TimeTradeServer();
      if(value<=0)
         value=TimeCurrent();
      if(value<=0)
         value=TimeLocal();
      if(value<=0)
         return(0);
      return((ulong)value*1000000000);
     }

   bool BuildBuildIdentityHash(uchar &hash[]) const
     {
      // Stage-07 integration baseline. Final release packaging will replace
      // this deterministic build identity with a source-tree provenance hash.
      const string identity="KatarinaBridgeStage07EA/build-700";
      uchar material[];
      if(!Kat1StringBytesNoNull(identity,CP_UTF8,material))
         return(false);
      const uchar key[]={};
      ArrayResize(hash,0);
      if(!CryptEncode(CRYPT_HASH_SHA256,material,key,hash))
         return(false);
      return(ArraySize(hash)==32);
     }

   bool QueueHeartbeat(void)
     {
      if(HasPendingControl())
         return(true);

      ulong sequence=0;
      if(!m_sequence.Next(0,sequence))
         return(false);

      uchar frame[];
      string error="";
      const ulong source_time_ns=SourceTimeNs();
      if(!Kat1BuildHeartbeat(sequence,
                             source_time_ns,
                             m_stream_id,
                             m_boot_id,
                             GetTickCount64(),
                             sequence,
                             m_latest_consumed_command_sequence,
                             0,
                             0,
                             source_time_ns,
                             1,
                             frame,
                             error))
         return(false);

      return(QueuePendingControl(frame,KAT1_MSG_HEARTBEAT));
     }

   bool ValidateInboundSequence(const SKat1Header &header)
     {
      if(header.sequence==0)
         return(false);

      if(m_latest_inbound_sequence==0)
        {
         m_latest_inbound_sequence=header.sequence;
         return(true);
        }

      if(header.sequence!=m_latest_inbound_sequence+1)
         return(false);

      m_latest_inbound_sequence=header.sequence;
      return(true);
     }

   bool HandleHello(const uchar &frame[],
                    const SKat1Header &header)
     {
      if(m_state!=KAT7_TRANSPORT_WAITING_HELLO)
         return(false);

      if(header.stream_id!=m_stream_id ||
         header.boot_id!=m_boot_id)
         return(false);

      SKat1HelloMessage hello;
      string error="";
      if(!Kat1DecodeHello(frame,hello,error))
         return(false);

      // Stage 07 is communication-only. Any request to arm execution is
      // rejected until later governed stages.
      if(hello.requested_execution_mode!=0)
         return(false);

      uchar account_id[];
      if(!Kat1BuildAccountId(m_broker_server,
                             m_broker_login,
                             account_id,
                             error))
         return(false);

      uchar build_hash[];
      if(!BuildBuildIdentityHash(build_hash))
         return(false);

      ulong response_sequence=0;
      if(!m_sequence.Next(0,response_sequence))
         return(false);

      uchar ack[];
      if(!Kat1BuildHelloAck(response_sequence,
                            SourceTimeNs(),
                            m_stream_id,
                            m_boot_id,
                            account_id,
                            m_broker_login,
                            (uint)TerminalInfoInteger(TERMINAL_BUILD),
                            KAT7_EA_BUILD_VERSION,
                            0,
                            NormalizeAccountMode(),
                            NormalizeTradeMode(),
                            0,
                            1,
                            (uchar)m_currency_digits,
                            (uchar)m_currency_digits,
                            build_hash,
                            1,
                            m_broker_server,
                            m_account_currency,
                            ack,
                            error))
         return(false);

      if(!QueuePendingControl(ack,KAT1_MSG_HELLO_ACK))
         return(false);

      m_latest_consumed_command_sequence=header.sequence;
      m_state=KAT7_TRANSPORT_ACK_PENDING;

      // Best effort now; if ZeroMQ is temporarily backpressured, Pump()
      // retries the exact same critical frame/sequence rather than allocating
      // a new sequence and creating a protocol gap.
      FlushPendingControl();
      return(true);
     }

   bool HandleInbound(const uchar &frame[])
     {
      SKat1Header header;
      string error="";
      if(!Kat1ValidateFrame(frame,header,error))
         return(false);

      if(header.stream_id!=m_stream_id ||
         header.boot_id!=m_boot_id)
         return(false);

      if(!ValidateInboundSequence(header))
         return(false);

      if(header.message_type==KAT1_MSG_HELLO)
         return(HandleHello(frame,header));

      if(header.message_type==KAT1_MSG_HEARTBEAT)
        {
         m_latest_consumed_command_sequence=header.sequence;
         return(true);
        }

      // Snapshot/reconciliation and all other commands are implemented by the
      // next Stage-07 recovery layer. Unknown critical input is fail-closed.
      return(false);
     }

   void Fault(void)
     {
      m_state=KAT7_TRANSPORT_FAULTED;
     }

public:
                     CKatStage07Transport(void)
     {
      m_endpoint="";
      m_stream_id=0;
      m_boot_id=0;
      m_broker_login=0;
      m_broker_server="";
      m_account_currency="";
      m_currency_digits=0;
      m_margin_mode=(ENUM_ACCOUNT_MARGIN_MODE)-1;
      m_trade_mode=(ENUM_ACCOUNT_TRADE_MODE)-1;
      m_state=KAT7_TRANSPORT_STOPPED;
      m_last_heartbeat_ms=0;
      m_latest_consumed_command_sequence=0;
      m_latest_inbound_sequence=0;
      m_configured=false;
      ArrayResize(m_pending_control,0);
      m_pending_message_type=0;
     }

   bool              Configure(const string endpoint,
                               const ulong stream_id,
                               const ulong boot_id,
                               const SKatAccountFacts &account)
     {
      if(endpoint=="" ||
         stream_id==0 ||
         boot_id==0 ||
         account.login==0 ||
         account.server=="" ||
         account.currency=="" ||
         account.currency_digits<0 ||
         account.currency_digits>8)
         return(false);

      m_endpoint=endpoint;
      m_stream_id=stream_id;
      m_boot_id=boot_id;
      m_broker_login=account.login;
      m_broker_server=account.server;
      m_account_currency=account.currency;
      m_currency_digits=account.currency_digits;
      m_margin_mode=account.margin_mode;
      m_trade_mode=account.trade_mode;
      m_configured=true;
      return(true);
     }

   virtual bool      Start(void)
     {
      if(!m_configured)
         return(false);

      if(!m_sequence.Init(m_stream_id,"MT5_TO_PYTHON"))
         return(false);

      const string identity="kat7-"+IntegerToString((long)m_stream_id);
      if(!m_wire.Start(m_endpoint,identity,256,256))
         return(false);

      m_state=KAT7_TRANSPORT_WAITING_HELLO;
      m_last_heartbeat_ms=0;
      m_latest_consumed_command_sequence=0;
      m_latest_inbound_sequence=0;
      ClearPendingControl();

      // Presence heartbeat advertises the bridge but never implies READY.
      // Queue first; Pump retries without sequence reuse if the DEALER is not
      // connected at the exact Start() instant.
      return(QueueHeartbeat());
     }

   virtual void      Stop(void)
     {
      m_wire.Stop();
      ClearPendingControl();
      m_state=KAT7_TRANSPORT_STOPPED;
     }

   virtual bool      IsReady(void) const
     {
      // Must remain false until snapshot + reconciliation is complete.
      return(false);
     }

   bool              IsRecovering(void) const
     {
      return(m_state==KAT7_TRANSPORT_RECOVERING);
     }

   bool              IsFaulted(void) const
     {
      return(m_state==KAT7_TRANSPORT_FAULTED);
     }

   virtual bool      PublishTick(const SKatCapturedTick &event)
     {
      // Market/event encoding is enabled only after communication recovery.
      return(false);
     }

   virtual bool      PublishTrade(const SKatCapturedTrade &event)
     {
      // Critical event encoding is enabled only after communication recovery.
      return(false);
     }

   virtual void      Pump(const int max_items,
                          const ulong max_microseconds)
     {
      if(m_state==KAT7_TRANSPORT_STOPPED ||
         m_state==KAT7_TRANSPORT_FAULTED)
         return;

      const ulong started=GetMicrosecondCount();

      // Always retry an already-sequenced control frame first.
      FlushPendingControl();

      int handled=0;

      while(handled<max_items)
        {
         if(max_microseconds>0 &&
            GetMicrosecondCount()-started>=max_microseconds)
            break;

         uchar frame[];
         if(!m_wire.ReceiveFrame(frame))
            break;

         if(!HandleInbound(frame))
           {
            Fault();
            return;
           }

         handled++;
        }

      const ulong now_ms=GetTickCount64();
      if(!HasPendingControl() &&
         now_ms-m_last_heartbeat_ms>=KAT7_HEARTBEAT_INTERVAL_MS)
        {
         if(!QueueHeartbeat())
           {
            Fault();
            return;
           }
         FlushPendingControl();
        }
     }
  };

#endif
