```mermaid
---
config:
  layout: dagre
---
flowchart LR
 subgraph RG_Admin["RG: Administracija"]
        VM1("VM-Admin")
  end
 subgraph VNet_A["VNet-Admin"]
        Peer("Peering Ryšys")
  end
 subgraph VNet_S["VNet-Sandelys"]
        NSG_Sub("<b>NSG-Subnet</b><br>Action: ALLOW<br>Port: 1433")
  end
 subgraph RG_Infra["RG: Infrastruktūra"]
    direction TB
        VNet_A
        VNet_S
  end
 subgraph Server_Defense["Serverio Apsauga"]
        NSG_VM("<b>NSG-VM</b><br>Action: DENY<br>Port: 1433")
        VM2("VM-Sandelis")
  end
 subgraph RG_Sand["RG: Sandėlys"]
        Server_Defense
  end
    VNet_A <--> Peer
    Peer <--> VNet_S
    VM1 == "1. SQL Užklausa" ==> Peer
    Peer == "2. Ateina į Tinklą" ==> NSG_Sub
    NSG_Sub == "3. Tinklas praleidžia" ==> NSG_VM
    NSG_VM -. "4. BLOKUOJAMA" .-> VM2

     VM1:::vm
     NSG_Sub:::allow
     NSG_VM:::deny
     VM2:::vm
    classDef vm fill:#fff3e0,stroke:#ff6f00,stroke-width:2px,color:black
    classDef allow fill:#dcedc8,stroke:#33691e,stroke-width:2px,color:black
    classDef deny fill:#ffcdd2,stroke:#b71c1c,stroke-width:2px,color:black
    classDef container fill:#f5f5f5,stroke:#616161,stroke-width:1px,stroke-dasharray: 5 5,color:black
    linkStyle 3 stroke:#b71c1c,stroke-width:4px,stroke-dasharray: 5 5,fill:none
    ```