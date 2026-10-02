#ifndef __KATARINA_TRANSPORT_PORT_MQH__
#define __KATARINA_TRANSPORT_PORT_MQH__

#include <Katarina/EventBuffer.mqh>

class CKatTransportPort
  {
public:
   virtual bool      Start(void)
     {
      return(false);
     }

   virtual void      Stop(void)
     {
     }

   virtual bool      IsReady(void) const
     {
      return(false);
     }

   virtual bool      PublishTick(const SKatCapturedTick &event)
     {
      return(false);
     }

   virtual bool      PublishTrade(const SKatCapturedTrade &event)
     {
      return(false);
     }

   virtual void      Pump(const int max_items,
                          const ulong max_microseconds)
     {
     }
  };

// Stage 06 deliberately has no working network transport.
// Stage 07 will provide concrete localhost ZeroMQ/TCP implementations.
class CKatNullTransport : public CKatTransportPort
  {
public:
   virtual bool      Start(void)
     {
      return(true);
     }

   virtual void      Stop(void)
     {
     }

   virtual bool      IsReady(void) const
     {
      return(false);
     }

   virtual bool      PublishTick(const SKatCapturedTick &event)
     {
      return(false);
     }

   virtual bool      PublishTrade(const SKatCapturedTrade &event)
     {
      return(false);
     }

   virtual void      Pump(const int max_items,
                          const ulong max_microseconds)
     {
     }
  };

#endif
