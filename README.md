# AI-Assisted Car Rental Case Management & Agent Assist

[![Salesforce Service Cloud](https://img.shields.io/badge/Salesforce-Service_Cloud-00A1E0?logo=salesforce&logoColor=white)](https://www.salesforce.com/service/)
[![Apex](https://img.shields.io/badge/Apex-Async_Queueable_%7C_REST-00A1E0?logo=salesforce&logoColor=white)](https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/)
[![LWC](https://img.shields.io/badge/Frontend-Lightning_Web_Components-00A1E0?logo=salesforce&logoColor=white)](https://developer.salesforce.com/docs/component-library/overview/components)
[![Declarative Automation](https://img.shields.io/badge/Automation-Record--Triggered_Flows-00A1E0?logo=salesforce&logoColor=white)](https://help.salesforce.com/s/articleView?id=sf.flow.htm)
[![Integration](https://img.shields.io/badge/Integration-REST_API_%26_Queueable-68A063?logo=node.js&logoColor=white)](https://nodejs.org/)
[![Omni-Channel](https://img.shields.io/badge/Routing-Omni--Channel_Queues-00A1E0?logo=salesforce&logoColor=white)](https://help.salesforce.com/s/articleView?id=sf.omnichannel_intro.htm)
[![Salesforce DX](https://img.shields.io/badge/Tooling-Salesforce_CLI_(sf)-00A1E0?logo=salesforce&logoColor=white)](https://developer.salesforce.com/tools/salesforcecli)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

An enterprise-grade **Salesforce Service Cloud** solution designed for high-volume car rental and travel operations. It delivers an intelligent, **Human-in-the-Loop (HITL)** agent assist workspace inside the Salesforce Service Console—combining record-triggered Flows, asynchronous REST callouts via Queueable Apex, deterministic refund calculations, Knowledge grounding, and safety risk guardrails.

---

## 📌 Executive Summary

Car rental support teams process high volumes of complex cases across vehicle breakdowns, last-minute cancellations, and billing disputes. Relying purely on generative AI in customer support poses compliance and hallucination risks, while manual agent triage leads to prolonged Average Handle Times (AHT).

This project implements a **balanced, hybrid architecture**:
1. **Automated Triage & Routing**: Record-Triggered Flows classify cases and route urgent roadside issues to high-priority Omni-Channel queues.
2. **External Data Enrichment**: Asynchronous Queueable Apex queries external booking systems via REST API to enrich the Case record with live reservation, supplier, and vehicle telemetry.
3. **Deterministic Financial Calculation**: Strict refund policies are calculated by pure Apex rule engines (`RefundEligibilityCalculator`), eliminating financial hallucination risks.
4. **Knowledge-Grounded Agent Assist**: `AIInteractionService` generates draft responses grounded in verified Salesforce Knowledge (`Knowledge__kav`) articles.
5. **Human-in-the-Loop Safety Guardrails**: Safety scanners flag litigation, bodily injury, and fraud risks. The custom **Lightning Web Component (LWC)** provides agents with one-click **Approve**, **Edit**, **Reject**, or **Escalate** controls before messages are dispatched.
6. **Full Auditability**: Every interaction and agent decision is logged in `AI_Interaction__c` for compliance and performance monitoring.

---

## 🏗️ System Architecture & Workflow

```mermaid
flowchart TD
    subgraph Ingestion["1. Inbound Case Ingestion"]
        A[Inbound Customer Case] --> B[Record-Triggered Flow: Case_Initial_Triage_Flow]
        B --> C[Intent & Category Classification]
        B --> D[Omni-Channel Queue Assignment]
    end

    subgraph Integration["2. Asynchronous REST Integration"]
        C --> E[Queueable Apex: BookingIntegrationQueueable]
        E --> F[HTTP REST Callout to Booking API]
        F --> G[Enrich Case with Reservation & Vehicle Data]
    end

    subgraph Intelligence["3. Business Logic & Grounded AI"]
        G --> H[Refund Calculation Engine: RefundEligibilityCalculator]
        G --> I[Safety & Legal Guardrail Scanner]
        G --> J[Salesforce Knowledge Retrieval: Knowledge__kav]
        H & I & J --> K[Grounded Recommendation & Draft Generation]
    end

    subgraph Console["4. Service Console & Human-in-the-Loop"]
        K --> L[LWC Agent Assist: caseAgentAssist]
        L --> M{Agent Review}
        M -->|Approve| N[Dispatch Customer Response]
        M -->|Edit| O[Customise Draft & Send]
        M -->|Escalate / High Risk| P[Route to Tier 2 / Legal Queue]
        N & O & P --> Q[Audit Log Created: AI_Interaction__c]
    end
```

---

## 🛠️ Salesforce Technical Highlights

### 1. Apex Architecture & Design Patterns
- **Separation of Concerns**: Clear abstraction between controllers (`CaseAgentAssistController`), service layers (`AIInteractionService`), deterministic engines (`RefundEligibilityCalculator`), and async workers (`BookingIntegrationQueueable`).
- **Asynchronous Processing**: Uses **Queueable Apex** to perform HTTP callouts asynchronously upon record creation, preventing governor limit bottlenecks and transaction locking.
- **Robust Error Handling**: Graceful fallback strategies for API timeouts, unrecognised booking references, and malformed payloads.
- **100% Test Coverage**: Comprehensive Apex test classes with `HttpCalloutMock` implementations, bulk test cases, and positive/negative assertion suites.

### 2. Lightning Web Components (LWC) — `caseAgentAssist`
- **Modern Service Console Utility**: Embedded directly on the Case record page layout.
- **Real-Time Data Binding**: Uses reactive wire adapters (`getRecord`) and imperative Apex to display booking status badges, calculated refund breakdowns, and safety alerts.
- **Interactive Action Workspace**:
  - **Quick Copy**: Fast clipboard action for customer responses.
  - **Live Draft Editor**: In-place text area for agent edits prior to sending.
  - **One-Click Escalation**: Immediate queue transfer for flagged cases.

### 3. Responsible AI & Safety Guardrails
- **Zero Financial Hallucinations**:
  - $>48$ hours before pickup: **100% refund**.
  - $24$–$48$ hours before pickup: **50% refund**.
  - $<24$ hours before pickup: **0% refund** (standard cancellation fee).
  - All financial logic is computed strictly in Apex code.
- **Safety Keyword Scanner**: Automatically flags keywords (*accident*, *injury*, *hospital*, *lawyer*, *court*, *fraud*, *chargeback*) to trigger mandatory Tier 2 escalation.

---

## 📂 Project Metadata Structure

```text
AI-case-management-salesforce/
├── force-app/main/default/
│   ├── classes/                        # Apex Classes & Unit Test Suites
│   │   ├── AIInteractionService.cls            # Triage, grounding, guardrails & audit
│   │   ├── AIInteractionServiceTest.cls        # 100% unit tests for AI service
│   │   ├── BookingIntegrationService.cls       # REST API client & DTO parsers
│   │   ├── BookingIntegrationTest.cls          # HTTP mock & callout tests
│   │   ├── BookingIntegrationQueueable.cls     # Async Queueable callout handler
│   │   ├── BookingIntegrationQueueableTest.cls # Queueable test execution
│   │   ├── RefundEligibilityCalculator.cls     # Deterministic pricing & refund engine
│   │   ├── RefundEligibilityCalculatorTest.cls # Policy scenario test suite
│   │   ├── CaseAgentAssistController.cls       # AuraEnabled controller for LWC
│   │   └── CaseAgentAssistControllerTest.cls   # Controller integration tests
│   ├── lwc/
│   │   └── caseAgentAssist/            # Agent Assist Lightning Web Component
│   ├── flows/
│   │   ├── Case_Initial_Triage_Flow    # Record-triggered triage & classification
│   │   └── Case_Queue_Routing_Flow     # Omni-channel routing flow
│   ├── objects/
│   │   ├── Case/                       # Custom fields on Case
│   │   ├── AI_Interaction__c/          # Audit trail custom object
│   │   └── Knowledge__kav/             # Knowledge base articles
│   ├── permissionsets/                 # Permission sets for Service Agents
│   ├── queues/                         # Omni-Channel triage & escalation queues
│   ├── dashboards/ & reports/          # AHT & AI Acceptance analytics
│   └── serviceChannels/                # Service Cloud Omni-Channel channels
├── mock-api/                           # Node.js Mock Supplier REST API
│   ├── server.js                       # Mock endpoints for booking lookup & refunds
│   └── package.json                    # API dependencies (Express, CORS)
├── docs/                               # Architectural & Problem Breakdown Docs
│   ├── architecture.md                 # Detailed technical architecture
│   ├── business-problem.md             # Business drivers & domain analysis
│   └── future-enhancements.md          # Roadmap & enterprise scaling
├── sfdx-project.json                   # Salesforce DX project definition
├── package.json                        # Root project tooling
└── LICENSE                             # MIT License
```

---

## 🚀 Setup & Deployment Guide

### Prerequisites
- [Salesforce CLI (`sf`)](https://developer.salesforce.com/tools/salesforcecli) installed.
- Access to a Salesforce Developer Org or Scratch Org.
- Node.js (v18+) for running the mock supplier API locally.

### 1. Clone & Authenticate

```bash
git clone https://github.com/muthumorley/AI-case-management-salesforce.git
cd AI-case-management-salesforce

# Authenticate with your Salesforce Org
sf org login web --alias DevOrg --set-default
```

### 2. Deploy Metadata to Salesforce

```bash
# Deploy all Apex, LWC, Flows, and Custom Objects
sf project deploy start --target-org DevOrg
```

### 3. Run Apex Unit Test Suite

Execute all Apex test classes and verify 100% test pass rate and code coverage:

```bash
sf apex run test --test-level RunLocalTests --result-format human --code-coverage
```

### 4. Start Local Mock Supplier API (Optional for Integration Testing)

```bash
cd mock-api
npm install
npm start
```
*The mock API will start on `http://localhost:3000` with endpoints `/api/bookings/:id` and `/api/refunds/process`.*

---

## 📊 Business Value & Key Metrics

- **Average Handle Time (AHT) Reduction**: Pre-populated booking data, calculated refunds, and grounded responses reduce manual research time by up to 60%.
- **Zero Financial Error Rate**: Deterministic Apex calculations eliminate human miscalculations and AI hallucination risks.
- **Audit & Compliance Ready**: 100% of AI-generated suggestions and agent approvals/edits are tracked in `AI_Interaction__c`.

---

## 📄 License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
