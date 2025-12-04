## 1. Création des Ressources

```bash
# Créer le réseau
openstack network create test-network

# Créer le subnet
openstack subnet create test-subnet --network test-network --subnet-range 192.168.100.0/24 --gateway 192.168.100.1 --dns-nameserver 8.8.8.8

# Créer le router
openstack router create test-router

# Connecter au réseau externe (adapter "public" si nécessaire)
openstack router set test-router --external-gateway public1

# Connecter le router au subnet
openstack router add subnet test-router test-subnet

# Créer une VM
openstack server create --flavor m1.small --image cirros --network test-network --key-name mykey test-vm

# Attendre que la VM soit active
openstack server list

# Récupérer l'IP de la VM
openstack server show test-vm -c addresses
```

## 2. Démarrer les Captures (Terminal 1)

```bash
# Identifier le namespace du router
docker exec neutron_l3_agent ip netns list

# Capturer sur le namespace router (remplacer qrouter-XXX par le bon)
docker exec neutron_l3_agent ip netns exec qrouter-XXXXX tcpdump -i any -n -v
```

## 3. Voir les Flows OVS Avant Trafic (Terminal 2)

```bash
# Flows actuels sur br-int
docker exec openvswitch_vswitchd ovs-ofctl dump-flows br-int

# Stats des ports
docker exec openvswitch_vswitchd ovs-ofctl dump-ports br-int
```

## 4. Générer du Trafic ICMP (Terminal 3)

```bash
# Récupérer le namespace router
docker exec neutron_l3_agent ip netns list

# Ping vers la VM (remplacer l'IP et le namespace)
docker exec neutron_l3_agent ip netns exec qrouter-XXXXX ping -c 50 192.168.100.X
```

## 5. Observer les Changements en Temps Réel

**Dans Terminal 2 (pendant le ping) :**

```bash
# Voir les flows qui matchent avec l'IP de la VM
docker exec openvswitch_vswitchd ovs-ofctl dump-flows br-int | grep 192.168.100.X

# Voir les stats des ports (compteurs qui augmentent)
docker exec openvswitch_vswitchd ovs-ofctl dump-ports br-int

# Voir les connexions dans le router namespace
docker exec neutron_l3_agent ip netns exec qrouter-XXXXX netstat -an
```

## 6. Générer du Trafic TCP

```bash
# Tester la connexion SSH vers la VM
docker exec neutron_l3_agent ip netns exec qrouter-XXXXX nc -zv 192.168.100.X 22

# Ou tenter plusieurs connexions
docker exec neutron_l3_agent ip netns exec qrouter-XXXXX telnet 192.168.100.X 22
```

## 7. Analyser les Détails OVS

```bash
# Flows avec statistiques détaillées
docker exec openvswitch_vswitchd ovs-ofctl dump-flows br-int --names

# Trier par nombre de paquets
docker exec openvswitch_vswitchd ovs-ofctl dump-flows br-int | sort -t, -k3 -nr

# Voir un port spécifique
docker exec openvswitch_vswitchd ovs-vsctl show
```

## 8. Analyser Couche Router/NAT

```bash
# Voir les routes dans le namespace
docker exec neutron_l3_agent ip netns exec qrouter-XXXXX ip route

# Voir les règles NAT
docker exec neutron_l3_agent ip netns exec qrouter-XXXXX iptables -t nat -L -n -v

# Voir les connexions actives (conntrack)
docker exec neutron_l3_agent ip netns exec qrouter-XXXXX cat /proc/net/nf_conntrack | grep 192.168.100.X
```

## 9. Test avec Floating IP (si configurée)

```bash
# Créer et associer une floating IP
openstack floating ip create public
openstack server add floating ip test-vm <FLOATING_IP>

# Depuis ton poste local
ping <FLOATING_IP>

# Observer le NAT
docker exec neutron_l3_agent ip netns exec qrouter-XXXXX iptables -t nat -L -n -v | grep <FLOATING_IP>
```

## 10. Capture OVS Détaillée

```bash
# Capturer avec ovs-tcpdump
docker exec openvswitch_vswitchd ovs-tcpdump -i br-int host 192.168.100.X
```

## 11. Nettoyage

```bash
openstack server delete test-vm
openstack router remove subnet test-router test-subnet
openstack router unset test-router --external-gateway
openstack router delete test-router
openstack subnet delete test-subnet
openstack network delete test-network
```

**Note importante** : Garde le Terminal 1 avec tcpdump ouvert pendant que tu génères du trafic dans Terminal 3, et observe les changements dans Terminal 2.



Le problème vient des permissions dans le conteneur. Voici les alternatives qui fonctionnent :

## Solution 1 : Utiliser bash -c

```bash
docker exec neutron_l3_agent bash -c "ip netns exec qrouter-c70e206a-0fe0-44de-aed8-772b41cb8c3b tcpdump -i any -n -v"
```

## Solution 2 : OVS tcpdump (plus simple)

```bash
# Capturer directement sur br-int
docker exec openvswitch_vswitchd ovs-tcpdump -i br-int -n -v
```

## Solution 3 : Depuis l'host (si accessible)

```bash
# Vérifier si les namespaces sont visibles depuis l'host
ip netns list

# Si oui, capturer directement
ip netns exec qrouter-c70e206a-0fe0-44de-aed8-772b41cb8c3b tcpdump -i any -n -v
```

## Solution 4 : Privilégier --privileged (si les autres échouent)

```bash
docker exec --privileged neutron_l3_agent ip netns exec qrouter-c70e206a-0fe0-44de-aed8-772b41cb8c3b tcpdump -i any -n -v
```

## Commandes Recommandées (sans tcpdump)

Si tcpdump reste problématique, utilise ces alternatives :

```bash
# 1. Voir les interfaces dans le namespace
docker exec neutron_l3_agent bash -c "ip netns exec qrouter-c70e206a-0fe0-44de-aed8-772b41cb8c3b ip addr"

# 2. Voir les routes
docker exec neutron_l3_agent bash -c "ip netns exec qrouter-c70e206a-0fe0-44de-aed8-772b41cb8c3b ip route"

# 3. Ping depuis le router
docker exec neutron_l3_agent bash -c "ip netns exec qrouter-c70e206a-0fe0-44de-aed8-772b41cb8c3b ping -c 5 192.168.100.X"

# 4. Voir les connexions
docker exec neutron_l3_agent bash -c "ip netns exec qrouter-c70e206a-0fe0-44de-aed8-772b41cb8c3b netstat -an"

# 5. Voir le NAT
docker exec neutron_l3_agent bash -c "ip netns exec qrouter-c70e206a-0fe0-44de-aed8-772b41cb8c3b iptables -t nat -L -n -v"
```

## Meilleure Approche : Analyser avec OVS

```bash
# Terminal 1 : Capturer sur OVS (ça marche toujours)
docker exec openvswitch_vswitchd ovs-tcpdump -i br-int -n -v

# Terminal 2 : Générer du trafic
docker exec neutron_l3_agent bash -c "ip netns exec qrouter-c70e206a-0fe0-44de-aed8-772b41cb8c3b ping -c 50 192.168.100.X"

# Terminal 3 : Observer les flows
docker exec openvswitch_vswitchd ovs-ofctl dump-flows br-int

# Puis voir les stats
docker exec openvswitch_vswitchd ovs-ofctl dump-ports br-int
```
