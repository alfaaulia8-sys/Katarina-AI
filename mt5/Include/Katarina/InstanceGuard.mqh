#ifndef __KATARINA_INSTANCE_GUARD_MQH__
#define __KATARINA_INSTANCE_GUARD_MQH__

class CKatInstanceGuard
  {
private:
   string m_name;
   double m_lease_value;
   int    m_ttl_seconds;
   ulong  m_last_refresh_ms;
   bool   m_acquired;

public:
                     CKatInstanceGuard(void)
     {
      m_name="";
      m_lease_value=0.0;
      m_ttl_seconds=10;
      m_last_refresh_ms=0;
      m_acquired=false;
     }

   bool              Acquire(const ulong login,
                             const int ttl_seconds=10)
     {
      m_ttl_seconds=(ttl_seconds<3 ? 3 : ttl_seconds);
      m_name="KAT_BRIDGE_LOCK_"+IntegerToString((long)login);

      if(!GlobalVariableCheck(m_name))
        {
         // Atomic mutex state must not be initialized with GlobalVariableSet:
         // another EA could acquire between Check and Set and then be clobbered.
         // GlobalVariableTemp creates a missing variable at 0 without rewriting
         // an already-existing variable.
         if(!GlobalVariableTemp(m_name) && !GlobalVariableCheck(m_name))
            return(false);
        }

      double current=0.0;
      if(!GlobalVariableGet(m_name,current))
         return(false);

      const double now=(double)TimeLocal();

      if(current>now)
         return(false);

      const double next=now+(double)m_ttl_seconds;
      if(!GlobalVariableSetOnCondition(m_name,next,current))
         return(false);

      m_lease_value=next;
      m_last_refresh_ms=GetTickCount64();
      m_acquired=true;
      return(true);
     }

   bool              Refresh(void)
     {
      if(!m_acquired)
         return(false);

      const ulong now_ms=GetTickCount64();
      if(now_ms-m_last_refresh_ms<2000)
         return(true);

      const double now=(double)TimeLocal();
      const double next=now+(double)m_ttl_seconds;

      if(!GlobalVariableSetOnCondition(m_name,next,m_lease_value))
        {
         m_acquired=false;
         return(false);
        }

      m_lease_value=next;
      m_last_refresh_ms=now_ms;
      return(true);
     }

   void              Release(void)
     {
      if(!m_acquired)
         return;

      GlobalVariableSetOnCondition(m_name,0.0,m_lease_value);
      m_acquired=false;
      m_lease_value=0.0;
     }

   bool              IsAcquired(void) const
     {
      return(m_acquired);
     }

   string            Name(void) const
     {
      return(m_name);
     }
  };

#endif
