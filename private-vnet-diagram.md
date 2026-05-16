# Private VNet Deployment Architecture Diagram

## Mermaid Diagram Code

Copy this code into https://mermaid.live/ to generate the diagram, then export as PNG.

```mermaid
graph TB
    subgraph VNet["Azure Virtual Network (10.2.0.0/16)"]
        subgraph FuncSubnet["Function Subnet (10.2.0.0/24)"]
            FuncApp["Function App<br/>(Basic Plan B1+)<br/>VNet Integrated<br/>Public Access: DISABLED"]
        end

        subgraph PESubnet["Private Endpoints Subnet (10.2.1.0/24)"]
            PE1["PE: Blob"]
            PE2["PE: File"]
            PE3["PE: Queue"]
            PE4["PE: Table"]
        end

        subgraph Resources["Resources"]
            Storage["Internal Storage Account<br/>(AzureWebJobsStorage)<br/>Public Access: DISABLED"]
            DNS["Private DNS Zones:<br/>- privatelink.blob.core.windows.net<br/>- privatelink.file.core.windows.net<br/>- privatelink.queue.core.windows.net<br/>- privatelink.table.core.windows.net"]
            Plan["App Service Plan<br/>(Basic B1)"]
        end

        FuncApp -->|Private Connection| PE1
        FuncApp -->|Private Connection| PE2
        FuncApp -->|Private Connection| PE3
        FuncApp -->|Private Connection| PE4

        PE1 -.->|Private Link| Storage
        PE2 -.->|Private Link| Storage
        PE3 -.->|Private Link| Storage
        PE4 -.->|Private Link| Storage

        DNS -.->|Name Resolution| PE1
        DNS -.->|Name Resolution| PE2
        DNS -.->|Name Resolution| PE3
        DNS -.->|Name Resolution| PE4

        FuncApp -.->|Uses| Plan
    end

    Target["Target Storage Account/<br/>Event Hub<br/>(Outside VNet)"]
    NewRelic["New Relic<br/>Logs API"]

    Target -->|Trigger<br/>Crosses VNet| FuncApp
    FuncApp -->|HTTPS<br/>Crosses VNet| NewRelic

    style VNet fill:#e1f5ff,stroke:#0078d4,stroke-width:3px
    style FuncSubnet fill:#fff4ce,stroke:#f4a306,stroke-width:2px
    style PESubnet fill:#f0f0f0,stroke:#666,stroke-width:2px
    style Resources fill:#ffe6e6,stroke:#d13438,stroke-width:2px
    style FuncApp fill:#ffeb99,stroke:#f4a306
    style Storage fill:#ffcccc,stroke:#d13438
    style DNS fill:#ffcccc,stroke:#d13438
    style Plan fill:#ffcccc,stroke:#d13438
    style Target fill:#d9b3ff,stroke:#7719aa
    style NewRelic fill:#00b3a4,stroke:#007e71
    style PE1 fill:#ccc,stroke:#666
    style PE2 fill:#ccc,stroke:#666
    style PE3 fill:#ccc,stroke:#666
    style PE4 fill:#ccc,stroke:#666
```

## Instructions:

### Step 1: Generate the Diagram
1. Go to https://mermaid.live/
2. Clear the default code
3. Paste the mermaid code above
4. The diagram will render automatically

### Step 2: Export as PNG
1. Click the **"Actions"** menu (top right)
2. Select **"PNG"** to download
3. Save as:
   - BlobForwarder: `blob-private-network-architecture.png`
   - EventHubForwarder: `eventhub-private-network-architecture.png`

### Step 3: Add to Repository
```bash
# For BlobForwarder
mv ~/Downloads/diagram.png screenshots/BlobForwarder/blob-private-network-architecture.png

# For EventHubForwarder (same diagram, just different name)
cp screenshots/BlobForwarder/blob-private-network-architecture.png screenshots/EventHub/eventhub-private-network-architecture.png
```

---

## Alternative: Draw.io Specification

If Mermaid doesn't give you the look you want, use Draw.io:

### Draw.io Steps:
1. Go to https://app.diagrams.net/
2. File → New Diagram
3. Choose "Blank Diagram"

### Components to Add:

**From Left Sidebar → Azure (search for Azure icons):**

1. **Create VNet Rectangle:**
   - Use "Rectangle" shape
   - Fill color: Light blue (#e1f5ff)
   - Border: Blue (#0078d4), 3px thick
   - Label: "Azure Virtual Network (10.2.0.0/16)"
   - Size: Large enough to contain everything below

2. **Inside VNet - Function Subnet:**
   - Rectangle
   - Fill: Light yellow (#fff4ce)
   - Label: "Function Subnet (10.2.0.0/24)"
   - Add **Azure Function** icon inside
   - Text below: "Function App (Basic Plan B1+, VNet Integrated, Public Access: DISABLED)"

3. **Inside VNet - Private Endpoints Subnet:**
   - Rectangle
   - Fill: Light gray (#f0f0f0)
   - Label: "Private Endpoints Subnet (10.2.1.0/24)"
   - Add 4 small gray boxes labeled:
     - PE: Blob
     - PE: File
     - PE: Queue
     - PE: Table

4. **Inside VNet - Bottom Section:**
   - **Storage Account** icon (pink box)
   - Text: "Internal Storage Account (AzureWebJobsStorage, Public Access: DISABLED)"

   - **DNS Zone** icon or badge
   - Text: "4 Private DNS Zones: privatelink.blob/file/queue/table.core.windows.net"

   - **App Service Plan** icon
   - Text: "App Service Plan (Basic B1)"

5. **Outside VNet - Left:**
   - **Storage Account** or **Event Hub** icon
   - Text: "Target Storage Account / Event Hub"
   - Dashed arrow to Function App
   - Label: "Trigger (crosses VNet)"

6. **Outside VNet - Right:**
   - Circle or cloud shape (teal color)
   - Text: "New Relic Logs API"
   - Solid arrow from Function App
   - Label: "HTTPS (crosses VNet)"

### Connections:
- Dashed lines from Function App to each Private Endpoint
- Dashed lines from Private Endpoints to Storage Account (label: "Private Link")
- Dashed lines from DNS Zones to Private Endpoints (label: "Name Resolution")

### Export:
- File → Export as → PNG
- Resolution: 300 DPI
- Transparent background: No

---

## Quick Text-Based Diagram (ASCII)

If you just need something quick for internal review:

```
╔═══════════════════════════════════════════════════════════════╗
║         Azure Virtual Network (10.2.0.0/16)                   ║
║                                                               ║
║  ┌─────────────────────────────────────────────────┐         ║
║  │ Function Subnet (10.2.0.0/24)                   │         ║
║  │                                                  │         ║
║  │   ┌────────────────────────────┐                │         ║
║  │   │    Function App            │                │         ║
║  │   │   (Basic Plan B1+)         │                │         ║
║  │   │   VNet Integrated          │                │         ║
║  │   │   Public Access: DISABLED  │                │         ║
║  │   └──────────┬─────────────────┘                │         ║
║  └──────────────┼──────────────────────────────────┘         ║
║                 │                                             ║
║  ┌──────────────▼────────────────────────────────┐           ║
║  │ Private Endpoints Subnet (10.2.1.0/24)        │           ║
║  │                                                │           ║
║  │  ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐     │           ║
║  │  │ PE:  │  │ PE:  │  │ PE:  │  │ PE:  │     │           ║
║  │  │ Blob │  │ File │  │Queue │  │Table │     │           ║
║  │  └───┬──┘  └───┬──┘  └───┬──┘  └───┬──┘     │           ║
║  └──────┼─────────┼─────────┼─────────┼─────────┘           ║
║         │         │         │         │                     ║
║         └─────────┴─────────┴─────────┘                     ║
║                   │                                          ║
║         ┌─────────▼──────────────────┐                      ║
║         │ Internal Storage Account   │                      ║
║         │ (AzureWebJobsStorage)      │                      ║
║         │ Public Access: DISABLED    │                      ║
║         └────────────────────────────┘                      ║
║                                                              ║
║  ┌──────────────────────────────────────────┐               ║
║  │ Private DNS Zones:                       │               ║
║  │ • privatelink.blob.core.windows.net      │               ║
║  │ • privatelink.file.core.windows.net      │               ║
║  │ • privatelink.queue.core.windows.net     │               ║
║  │ • privatelink.table.core.windows.net     │               ║
║  └──────────────────────────────────────────┘               ║
║                                                              ║
║  ┌────────────────────┐                                     ║
║  │ App Service Plan   │                                     ║
║  │ (Basic B1)         │                                     ║
║  └────────────────────┘                                     ║
╚═══════════════════════════════════════════════════════════════╝
         ▲                                    │
         │                                    │
         │ Trigger                            │ HTTPS
         │ (crosses VNet)                     │ (crosses VNet)
         │                                    ▼
┌────────┴─────────┐                ┌─────────────────┐
│ Target Storage   │                │   New Relic     │
│ Account /        │                │   Logs API      │
│ Event Hub        │                └─────────────────┘
└──────────────────┘
```

---

## My Recommendation

**Use Mermaid Live** (Option 1) because:
- ✅ Fastest - renders instantly
- ✅ Free - no account needed
- ✅ Easy to iterate - just edit the code
- ✅ Can export high-quality PNG
- ✅ I've already written the code for you

Just copy the mermaid code, paste it into https://mermaid.live/, and export as PNG!

Would you like me to adjust anything in the diagram specification?