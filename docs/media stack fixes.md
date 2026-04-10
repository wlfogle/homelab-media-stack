pct set 213 -net0 name=eth0,bridge=vmbr0,ip=192.168.12.213/24,gw=192.168.12.1
pct set 213 -nameserver 192.168.12.244
pct reboot 213

pct stop 213
pct set 213 -memory 1024 -swap 1024
pct start 213
sleep 5
pct exec 213 -- ping -c1 -W2 google.com

then:

pct exec 213 -- apt-get update
pct exec 213 -- apt-get install -y deluged deluge-web deluge-console
pct exec 213 -- systemctl enable --now deluged
pct exec 213 -- bash -c "deluge-web --fork -i 0.0.0.0"
pct exec 213 -- ss -tlnp | grep 8112

pct set 213 --mp0 /mnt/hdd,mp=/data
pct set 213 --startup order=6,up=20,down=20
pct set 213 --onboot 1
