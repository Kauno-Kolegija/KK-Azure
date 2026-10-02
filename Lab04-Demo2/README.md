az group create `
  --name RG-DEMO-NETWORK `
  --location polandcentral

  az deployment group create `
  --resource-group RG-DEMO-NETWORK `
  --template-file .\Demo-Network\main.bicep `
  --parameters adminPassword='TavoDemoSlaptazodis'

Gyva demonstracija paskaitoje:
1. Parodome VNet-A
    * address space;
    * Subnet-Web;
    * Subnet-DB.
2. Parodome dvi Web VM
    * abi tame pačiame subnet;
    * skirtingi Private IP;
    * abi priklauso ASG-Web.
3. Parodome DB VM
    * kitame subnet;
    * tik Private IP;
    * priklauso ASG-DB.
4. Parodome NIC
    * Web-01 turi Private IP + Public IP;
    * Web-02 ir DB-01 tik Private IP.
5. Prisijungiame prie Web-01
    * ir paleidžiame: curl http://<DB-01-private-IP>
6. Paaiškiname:
    * skirtingi subnetai;
    * tas pats VNet;
    * komunikacija veikia per Private IP.
7. ASG demonstracija
    * Tada atidarome DB NSG taisyklę:
        Source: ASG-Web
        Destination: ASG-DB
        Port: 80
        Action: Allow    
8. Sulaužome ryšį ir sukuriame NSG taisyklę
        Priority: 150
        Source: ASG-Web
        Destination: ASG-DB
        Port: 80
        Protocol: TCP
        Action: Deny
9. Network Watcher
    * Dabar žinome, kad neveikia. Bet kaip administratorius nustato kodėl?
    * Network Watcher → IP Flow Verify
        source VM / NIC;
        destination;
        TCP;
        port 80.
10 Peering demonstracija
    * Iš Web-01: curl http://<APP-01-private-IP>
    * Parodome, kad nėra ryšio tarp VNet-A ir VNet-B
    * Sukuriame ryšį

Tai praktiškai visa šiandienos paskaita vienoje infrastruktūroje