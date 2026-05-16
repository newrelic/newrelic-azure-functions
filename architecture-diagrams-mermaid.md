# Architecture Diagrams - Mermaid Code

Copy each diagram code into https://mermaid.live/ and export as PNG.

---

## 1. BlobForwarder - Standard Deployment

**Save as:** `screenshots/BlobForwarder/blob-standard-architecture.png`

```mermaid
flowchart LR
    Customer["Customer/Application"]

    subgraph Azure["Azure Subscription"]
        Target["Target Storage Account<br/>Customer's existing storage<br/>Contains log blobs"]

        subgraph ResourceGroup["Resource Group - Created by ARM Template"]
            FuncApp["Function App<br/>nrlogs-blobforwarder-xxx<br/><br/>Runtime: Node.js 22<br/>Trigger: Blob Storage<br/>Consumption Plan Y1<br/>Public Access: Enabled"]

            ServicePlan["App Service Plan<br/>SKU: Y1 Dynamic<br/>Consumption/Serverless"]

            InternalStorage["Internal Storage Account<br/>nrlogsxxx<br/><br/>Purpose: AzureWebJobsStorage<br/>Function state & logs<br/>Public Access: Enabled"]
        end
    end

    subgraph External["External Services"]
        GitHub["GitHub Releases<br/>github.com/newrelic/<br/>newrelic-azure-functions"]
        NewRelic["New Relic<br/>Logs API<br/>log-api.newrelic.com"]
    end

    Customer -->|"1. Writes log files"| Target
    Target -->|"2. Blob trigger fires"| FuncApp
    FuncApp --> ServicePlan
    FuncApp -->|"3. Reads & writes state"| InternalStorage
    FuncApp -->|"4. Forwards logs HTTPS"| NewRelic
    GitHub -.->|"ZipDeploy<br/>Deploys code"| FuncApp

    style Customer fill:#d9b3ff,stroke:#7719aa,stroke-width:2px
    style Azure fill:#f0f8ff,stroke:#0078d4,stroke-width:2px
    style ResourceGroup fill:#fff,stroke:#0078d4,stroke-width:2px
    style External fill:#f5f5f5,stroke:#666,stroke-width:2px
    style Target fill:#b3d9ff,stroke:#0078d4,stroke-width:2px
    style ServicePlan fill:#ffcccc,stroke:#d13438,stroke-width:2px
    style FuncApp fill:#ffeb99,stroke:#f4a306,stroke-width:3px
    style InternalStorage fill:#ffcccc,stroke:#d13438,stroke-width:2px
    style GitHub fill:#e6e6e6,stroke:#666,stroke-width:2px
    style NewRelic fill:#00b3a4,stroke:#007e71,stroke-width:3px
```

---

## 2. BlobForwarder - Private VNet Deployment

**Save as:** `screenshots/BlobForwarder/blob-private-network-architecture.png`

```mermaid
flowchart TB
 subgraph VNet["VNet: nrlogsxxxxx-virtual-network | 10.2.0.0/16"]
    direction TB
        FuncApp["Function App<br>nrlogs-blobforwarder-xxx<br><br>Runtime: Node.js 22<br>VNet Integrated<br>Public Access: Disabled"]
        ServicePlan["App Service Plan<br>Required for VNet Integration"]
        PE1["Private Endpoint<br>Blob Service<br>Subnet: 10.2.1.0/24"]
        PE2["Private Endpoint<br>File Service<br>Subnet: 10.2.1.0/24"]
        PE3["Private Endpoint<br>Queue Service<br>Subnet: 10.2.1.0/24"]
        PE4["Private Endpoint<br>Table Service<br>Subnet: 10.2.1.0/24"]
        InternalStorage["Internal Storage Account<br>nrlogsxxxxx<br><br>Purpose: AzureWebJobsStorage<br>Network ACLs: Deny All Public<br>Public Access: Disabled"]
        DNS["Private DNS Zones x4<br>privatelink.blob.core.windows.net<br>privatelink.file.core.windows.net<br>privatelink.queue.core.windows.net<br>privatelink.table.core.windows.net"]
  end
 subgraph ResourceGroup["Resource Group"]
        VNet
  end
 subgraph Azure["Azure Subscription"]
        Target["Target Storage Account<br>with log blobs in containers"]
        ResourceGroup
  end
 subgraph External["External Services"]
        GitHub["GitHub Releases<br>github.com/newrelic/<br>newrelic-azure-functions"]
        NewRelic["New Relic<br>Logs API<br>"]
  end
    Customer["Customer Application"] -- "1. Writes log files" --> Target
    Target -- "2. Blob trigger fires" --> FuncApp
    FuncApp --> ServicePlan
    FuncApp <-- "3. Private connection" --> PE1 & PE2 & PE3 & PE4
    PE1 <-- Private Link --> InternalStorage
    PE2 <-- Private Link --> InternalStorage
    PE3 <-- Private Link --> InternalStorage
    PE4 <-- Private Link --> InternalStorage
    DNS -. Name resolution<br>to Private IPs .-> PE1 & PE2 & PE3 & PE4
    FuncApp -- "4. Forwards logs HTTPS<br>Crosses VNet boundary" --> NewRelic
    GitHub -. "Run-from-Package<br>Downloads &amp; mounts" .-> FuncApp

    Target@{ shape: rect}
    style FuncApp fill:#ffeb99,stroke:#f4a306,stroke-width:3px
    style ServicePlan fill:#ffcccc,stroke:#d13438,stroke-width:2px
    style PE1 fill:#ccc,stroke:#666,stroke-width:2px
    style PE2 fill:#ccc,stroke:#666,stroke-width:2px
    style PE3 fill:#ccc,stroke:#666,stroke-width:2px
    style PE4 fill:#ccc,stroke:#666,stroke-width:2px
    style InternalStorage fill:#ffcccc,stroke:#d13438,stroke-width:2px
    style DNS fill:#ddd,stroke:#666,stroke-width:2px
    style VNet fill:#e1f5ff,stroke:#0078d4,stroke-width:3px
    style Target fill:#b3d9ff,stroke:#0078d4,stroke-width:2px
    style ResourceGroup fill:#fff,stroke:#0078d4,stroke-width:2px
    style GitHub fill:#e6e6e6,stroke:#666,stroke-width:2px
    style NewRelic fill:#00b3a4,stroke:#007e71,stroke-width:3px
    style Customer fill:#d9b3ff,stroke:#7719aa,stroke-width:2px
    style Azure fill:#f0f8ff,stroke:#0078d4,stroke-width:2px
    style External fill:#f5f5f5,stroke:#666,stroke-width:2px
```

---

## 3. EventHubForwarder - Standard Deployment

**Save as:** `screenshots/EventHub/eventhub-standard-architecture.png`

```mermaid
flowchart TB
 subgraph EventHubNS["Event Hub Namespace"]
        EventHub["Event Hub with logs<br><br>Consumer Group<br>Partitions<br><br>Shared Access Policy:<br>RootManageSharedAccessKey"]
  end
 subgraph ResourceGroup["Resource Group"]
        FuncApp["Function App<br>nrlogs-eventhubforwarder-xxx<br><br>Runtime: Node.js 22<br>Public Access: Enabled"]
        ServicePlan["App Service Plan<br>"]
        InternalStorage["Internal Storage Account<br>nrlogsxxxxx<br><br>Purpose: AzureWebJobsStorage<br>Function state,<br>checkpoints, leases<br>Public Access: Enabled"]
  end
 subgraph Azure["Azure Subscription"]
        ActivityLog["Azure Activity Log<br><br>Diagnostic Setting<br>Exports to Event Hub<br><br>Categories:<br>Administrative, Alert,<br>Policy, Autoscale, etc."]
        EventHubNS
        ResourceGroup
  end
 subgraph External["External Services"]
        GitHub["GitHub Releases<br>github.com/newrelic/<br>newrelic-azure-functions"]
        NewRelic["New Relic<br>Logs API<br>"]
  end
    Customer["Customer<br>Application"] -- Generates Logs --> ActivityLog
    ActivityLog -- "2. Streams logs" --> EventHub
    EventHub -- "3. Event Hub trigger<br>delivers batch" --> FuncApp
    FuncApp --> ServicePlan
    FuncApp -- "4. Manages checkpoints<br>&amp; execution state" --> InternalStorage
    FuncApp -- "5. Forwards logs HTTPS" --> NewRelic
    GitHub -. ZipDeploy<br>Deploys code .-> FuncApp

    style EventHub fill:#b3d9ff,stroke:#0078d4,stroke-width:2px
    style FuncApp fill:#ffeb99,stroke:#f4a306,stroke-width:3px
    style ServicePlan fill:#ffcccc,stroke:#d13438,stroke-width:2px
    style InternalStorage fill:#ffcccc,stroke:#d13438,stroke-width:2px
    style ActivityLog fill:#d9b3ff,stroke:#7719aa,stroke-width:2px
    style EventHubNS fill:#b3d9ff,stroke:#0078d4,stroke-width:2px
    style ResourceGroup fill:#fff,stroke:#0078d4,stroke-width:2px
    style GitHub fill:#e6e6e6,stroke:#666,stroke-width:2px
    style NewRelic fill:#00b3a4,stroke:#007e71,stroke-width:3px
    style Customer fill:#d9b3ff,stroke:#7719aa,stroke-width:2px
    style Azure fill:#f0f8ff,stroke:#0078d4,stroke-width:2px
    style External fill:#f5f5f5,stroke:#666,stroke-width:2px
```

---

## 4. EventHubForwarder - Private VNet Deployment

**Save as:** `screenshots/EventHub/eventhub-private-network-architecture.png`

```mermaid
flowchart TB
 subgraph EventHubNS["Event Hub Namespace"]
        EventHub["Event Hub with logs<br><br>Consumer Group<br>Partitions<br><br>Shared Access Policy:<br>RootManageSharedAccessKey"]
  end
 subgraph VNet["VNet: nrlogsxxxxx-virtual-network | 10.2.0.0/16"]
    direction TB
        FuncApp["Function App<br>nrlogs-eventhubforwarder-xxx<br><br>Runtime: Node.js 22<br>VNet Integrated<br>Public Access: Disabled"]
        ServicePlan["App Service Plan<br>Required for VNet Integration"]
        PE1["Private Endpoint<br>Blob Service<br>Subnet: 10.2.1.0/24"]
        PE2["Private Endpoint<br>File Service<br>Subnet: 10.2.1.0/24"]
        PE3["Private Endpoint<br>Queue Service<br>Subnet: 10.2.1.0/24"]
        PE4["Private Endpoint<br>Table Service<br>Subnet: 10.2.1.0/24"]
        InternalStorage["Internal Storage Account<br>nrlogsxxxxx<br><br>Purpose: AzureWebJobsStorage<br>Checkpoints, leases, state<br>Network ACLs: Deny All Public<br>Public Access: Disabled"]
        DNS["Private DNS Zones x4<br>privatelink.blob.core.windows.net<br>privatelink.file.core.windows.net<br>privatelink.queue.core.windows.net<br>privatelink.table.core.windows.net"]
  end
 subgraph ResourceGroup["Resource Group"]
        VNet
  end
 subgraph Azure["Azure Subscription"]
        ActivityLog["Azure Activity Log<br><br>Diagnostic Setting<br>Exports to Event Hub<br><br>Categories:<br>Administrative, Alert,<br>Policy, Autoscale, etc."]
        EventHubNS
        ResourceGroup
  end
 subgraph External["External Services"]
        GitHub["GitHub Releases<br>github.com/newrelic/<br>newrelic-azure-functions"]
        NewRelic["New Relic<br>Logs API<br>"]
  end
    Customer["Customer<br>Application"] -- Generates logs --> ActivityLog
    ActivityLog -- "2. Streams logs" --> EventHub
    EventHub -- "3. Event Hub trigger<br>delivers batch" --> FuncApp
    FuncApp --> ServicePlan
    FuncApp <-- "4. Private connection" --> PE1 & PE2 & PE3 & PE4
    PE1 <-- Private Link --> InternalStorage
    PE2 <-- Private Link --> InternalStorage
    PE3 <-- Private Link --> InternalStorage
    PE4 <-- Private Link --> InternalStorage
    DNS -. Name resolution<br>to Private IPs .-> PE1 & PE2 & PE3 & PE4
    FuncApp -- "5. Forwards logs HTTPS<br>Crosses VNet boundary" --> NewRelic
    GitHub -. "Run-from-Package<br>Downloads &amp; mounts" .-> FuncApp

    style EventHub fill:#b3d9ff,stroke:#0078d4,stroke-width:2px
    style FuncApp fill:#ffeb99,stroke:#f4a306,stroke-width:3px
    style ServicePlan fill:#ffcccc,stroke:#d13438,stroke-width:2px
    style PE1 fill:#ccc,stroke:#666,stroke-width:2px
    style PE2 fill:#ccc,stroke:#666,stroke-width:2px
    style PE3 fill:#ccc,stroke:#666,stroke-width:2px
    style PE4 fill:#ccc,stroke:#666,stroke-width:2px
    style InternalStorage fill:#ffcccc,stroke:#d13438,stroke-width:2px
    style DNS fill:#ddd,stroke:#666,stroke-width:2px
    style VNet fill:#e1f5ff,stroke:#0078d4,stroke-width:3px
    style ActivityLog fill:#d9b3ff,stroke:#7719aa,stroke-width:2px
    style EventHubNS fill:#b3d9ff,stroke:#0078d4,stroke-width:2px
    style ResourceGroup fill:#fff,stroke:#0078d4,stroke-width:2px
    style GitHub fill:#e6e6e6,stroke:#666,stroke-width:2px
    style NewRelic fill:#00b3a4,stroke:#007e71,stroke-width:3px
    style Customer fill:#d9b3ff,stroke:#7719aa,stroke-width:2px
    style Azure fill:#f0f8ff,stroke:#0078d4,stroke-width:2px
    style External fill:#f5f5f5,stroke:#666,stroke-width:2px
```

---

## Instructions

### Step 1: Generate Each Diagram
1. Go to https://mermaid.live/
2. Copy one of the mermaid code blocks above (between ```mermaid tags)
3. Paste into the editor
4. The diagram will render automatically

### Step 2: Export as PNG
1. Click **"Actions"** button (top right)
2. Select **"PNG"**
3. Save with the filename specified above

### Step 3: Move to Screenshots Folder
```bash
# After downloading all 4 diagrams, move them:
mv ~/Downloads/blob-standard-architecture.png screenshots/BlobForwarder/
mv ~/Downloads/blob-private-network-architecture.png screenshots/BlobForwarder/
mv ~/Downloads/eventhub-standard-architecture.png screenshots/EventHub/
mv ~/Downloads/eventhub-private-network-architecture.png screenshots/EventHub/
```

---

## Alternative: Use Draw.io for Better Layout Control

If Mermaid Live has overlapping text/boxes, I recommend using **Draw.io** (https://app.diagrams.net/) instead:

### Why Draw.io is Better for Complex Diagrams:
- ✅ Full control over component positioning
- ✅ No text overlap - you manually place everything
- ✅ Built-in Azure icon library
- ✅ Professional output
- ✅ Easy to adjust spacing

### Quick Steps:
1. Open https://app.diagrams.net/
2. File → New → Blank Diagram
3. Search for "Azure" in left panel to get icons
4. Manually recreate each diagram using the descriptions in this file
5. Export as PNG (File → Export as → PNG)

---

## Mermaid Limitations

If you're seeing overlapping boxes in Mermaid Live, this is a known limitation with:
- **Deep nesting** (3+ levels of subgraphs)
- **Complex layouts** with many connections
- **Long text labels** inside nested boxes

**Solutions:**
1. **Use Draw.io** (recommended for production diagrams)
2. **Export from Mermaid and edit in image editor** (quick fix)
3. **Simplify the diagrams** (remove some detail)

---

## Color Legend

- **Purple** - Customer/User/Azure Resources
- **Light Blue** - Azure Storage/Event Hub services
- **Yellow** - Function App
- **Pink/Red** - Internal Storage Account
- **Gray** - Private Endpoints & DNS
- **Teal** - New Relic (destination)
- **Light Blue Box** - Virtual Network boundary

---

## Key Differences Shown

### Standard vs Private VNet:
- **Standard**: All components have public access, no VNet boundary
- **Private VNet**: Function App and Internal Storage inside VNet, accessed via Private Endpoints

### BlobForwarder vs EventHubForwarder:
- **BlobForwarder**: Triggered by blob uploads to Storage Account
- **EventHubForwarder**: Triggered by events from Event Hub (fed by Activity Logs)