# locallab
Local Lab Config

## desired state

```bash
vol0 sötti so usgseh:
nasim01::> vol show
Vserver   Volume       Aggregate    State      Type       Size  Available Used%
--------- ------------ ------------ ---------- ---- ---------- ---------- -----
nasim01-01  
         vol0         aggr0_nasim01_01  
                                   online     RW          4GB     2.83GB   25%
```

## ssh

`alias nasim='sshpass -p tabstop1 ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o PreferredAuthentications=password -o PubkeyAuthentication=no admin@192.168.123.201'`


## shutdown

wichtig, wänn de laptop abefahrsch oder hibernatisch, filer mi "halt" uf de console stoppe und dänn d vm force off. Susch chas si, das koruppti disks häsch.

