# Incident 13 — Quorum Loss (Consul/etcd)

## Scenario
A 3-node Consul/etcd cluster loses 2 nodes, dropping below the quorum threshold (2/3). The cluster becomes read-only or unavailable.

## Symptoms
- `No cluster leader` / `failed to find a viable cluster`
- Consul UI shows nodes as failed
- etcd: `etcdserver: request timed out`
- All writes to service discovery fail

## Simulate
```bash
# Start 3-node cluster
docker compose up -d

# Wait for cluster to form (30s)
sleep 30
docker exec incident-consul-1 consul members

# Kill 2 nodes to break quorum
docker stop incident-consul-2 incident-consul-3
docker exec incident-consul-1 consul members
# Should show: No cluster leader
```

## Diagnosis
```bash
# Check cluster members
docker exec incident-consul-1 consul members

# Check leader
docker exec incident-consul-1 consul operator raft list-peers

# etcd equivalent
etcdctl endpoint status --cluster
etcdctl member list
```

## Resolution
```bash
# Restart failed nodes
docker start incident-consul-2 incident-consul-3

# If nodes can't rejoin, force new cluster (DANGEROUS - data loss risk)
# consul agent -server -bootstrap-expect=1 ...

# etcd recovery
etcdctl member remove <dead-member-id>
# Then restart with new member
```

## Prevention
- Always run odd number of nodes (3, 5, 7)
- Monitor `consul_raft_peers` < quorum threshold
- Spread nodes across availability zones
- Regular snapshots: `consul snapshot save backup.snap`

## Post-Incident
- MTTR target: < 30 min
- Root cause: 2 of 3 nodes failed simultaneously (no HA across AZs)
