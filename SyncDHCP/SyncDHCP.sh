#! /usr/bin/bash
Flag="/tmp/SyncDHCP.running"
Src="/etc/pihole/dhcp.leases"

function Msg {
   printf "%s - %s\n" $(date +%u%m%d%H%M%S) "$*" 
}

function Stop {
   Msg "Stopping SyncDHCP service..."
   rm -f $Flag
   proc=$(ps -aux | awk '/inotifywait.*dhcp\.leases/{print $2}')
   [ -n "$proc" ] && kill -HUP $proc
   sleep 3     # Wait for filesystem cleanup
}

function Start {
   Msg "Starting SyncDHCP service..."
   Dst=$(mktemp)
   Tmp=$(mktemp)

   # Modify these target names to conform to your deployment
   if [ $(hostname) == "dns1" ]
   then
      Target=dns2
   else
      Target=dns1
   fi

   # Create the "run flag file"
   touch $Flag
   while [ -e $Flag ]
   do
      inotifywait -e modify $Src | \
      while read -r f a
      do
      size=$(cksum $Src | awk '{print $2}')
      if [ "$size" -ne 0 ]
      then
            awk '$4!="*"{printf "%s %s\n",$3,$4}' $Src | sort -k3 > $Tmp
            if ! cmp -s $Dst $Tmp
            then
                  diff $Dst $Tmp | awk '$1~/<|>/{
                     if ($1~/</)printf "released %s %s\n",$2,$3;
                     if ($1~/>/)printf "assigned %s %s\n",$2,$3;
                  }'
               scp $Tmp root@$Target:/etc/pihole/custom.list > /dev/null && \
               ssh root@$Target "chmod 744 /etc/pihole/custom.list;pihole restartdns reload" && \
               cp $Tmp $Dst && \
               Msg "Updated custom.list on $Target" 
            fi
      fi
      done
   done
   rm -f $Dst 
   rm -f $Tmp 
}

function Restart {
   Stop
   Start
}

case "$1" in
   Start)
      Start
      ;;
   Stop)
      Stop
      ;;
   Restart)
      Restart
      ;;
   Status)
      systemctl status SyncDHCP.service
      ;;
   *)
      echo "Usage: $0 {Start|Stop|Restart|Status}"
      ;;
esac
