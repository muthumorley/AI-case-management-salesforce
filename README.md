AI-Assisted Car Rental Case Management System

A Salesforce Service Cloud project that helps customer support agents handle car rental cases faster and more safely.

The system uses Salesforce Flow, Apex, Queueable Apex, REST API, Knowledge, and LWC to automatically analyze cases, retrieve booking information, calculate refunds, and provide AI-assisted responses for agents.


How It Works

Customer creates Case
        ↓
Salesforce Flow
        ↓
Case is classified
        ↓
Booking information retrieved
from external REST API
        ↓
Apex checks:
• Customer intent
• Urgency
• Refund eligibility
• Safety / legal risks
        ↓
Knowledge articles provide
approved information
        ↓
LWC shows recommendation
to Support Agent
        ↓
Agent:
Approve / Edit / Reject / Escalate
        ↓
Interaction is recorded



Main Features

1. Case Classification

The system identifies common car rental requests:

* Vehicle Breakdown
* Cancellation
* Billing
* Booking Change
* General Enquiry

Urgent cases such as vehicle breakdowns, accidents, or injuries can be flagged for immediate attention.

2. External Booking Integration

The system uses a REST API to retrieve booking information such as:

* Vehicle
* Supplier
* Pickup location
* Booking status
* Payment status

The API call is handled asynchronously using Queueable Apex.

3. Refund Calculator

Refund calculations are handled by Apex rather than AI.

Example:

Cancellation Time	Refund
48+ hours before pickup	100%
24–48 hours	50%
Less than 24 hours	0%

This ensures that financial calculations follow fixed business rules.

4. Knowledge-Based Responses

Salesforce Knowledge provides approved information for topics such as:

* Roadside assistance
* Cancellation policy
* Refund policy
* Security deposits

The AI recommendation is based on these approved sources instead of relying only on generated information.

5. Safety & Legal Guardrails

The system checks cases for potentially sensitive situations such as:

* Accident
* Injury
* Hospital
* Lawyer
* Court
* Fraud
* Chargeback

When a serious issue is detected:

Case
 ↓
Safety / Legal Risk Detected
 ↓
AI response is restricted
 ↓
Human review required
 ↓
Agent escalates the case

6. Agent Assist LWC

A Lightning Web Component is displayed on the Case page.

The agent can:

* View the case summary
* See the AI recommendation
* View the Knowledge source
* Edit the response
* Approve the response
* Reject the response
* Escalate the case

7. Audit Trail

Every AI interaction is stored in a custom object:

AI_Interaction__c

Example:

Case
 └── AI Interaction
      ├── Intent
      ├── Confidence
      ├── Recommendation
      ├── Agent Action
      ├── Override Reason
      └── Status

This provides a record of what the AI recommended and what the human agent ultimately did.

⸻


Salesforce Architecture

                 CUSTOMER
                    │
                    ▼
              Salesforce Case
                    │
                    ▼
             Record-Triggered Flow
                    │
          ┌─────────┴─────────┐
          ▼                   ▼
   Queueable Apex         AI Apex Service
          │                   │
          ▼                   ▼
   External Booking      Knowledge + Rules
       REST API               │
          │                   │
          └─────────┬─────────┘
                    ▼
             Case Agent Assist
                   LWC
                    │
                    ▼
             Support Agent
                    │
        ┌───────────┼───────────┐
        ▼           ▼           ▼
      Approve      Edit       Escalate
        │           │           │
        └───────────┼───────────┘
                    ▼
            AI_Interaction__c


Salesforce Technologies

Technology	Purpose
Salesforce Service Cloud	Customer cases
Flow	Case automation and triage
Apex	Business logic
Queueable Apex	Asynchronous API callouts
REST API	External booking integration
Salesforce Knowledge	Approved support information
LWC	Agent interface
Custom Objects	AI audit history
Permission Sets	Security
Reports & Dashboards	Operational reporting
Apex Tests	Automated testing



Project Structure

force-app/main/default/
├── classes/
│   ├── AIInteractionService.cls
│   ├── BookingIntegrationService.cls
│   ├── BookingIntegrationQueueable.cls
│   ├── CaseAgentAssistController.cls
│   └── RefundEligibilityCalculator.cls
│
├── lwc/
│   └── caseAgentAssist/
│
├── flows/
│   └── Case_Initial_Triage_Flow.flow-meta.xml
│
├── objects/
│   ├── Case/
│   └── AI_Interaction__c/
│
├── permissionsets/
│   └── Case_AI_Support_Agent.permissionset-meta.xml
│
├── reports/
│
└── dashboards/

 
 
 Testing

The project includes Apex unit tests covering:

* Refund calculations
* REST API integration
* Queueable Apex
* AI case processing
* Guardrails
* LWC controller

Target:

50 tests — 100% passing — ~95% code coverage

 Security

The project follows Salesforce security best practices:

* Permission Set instead of modifying profiles
* Field-Level Security
* Controlled access to AI-related fields
* Audit records for AI interactions
* Human approval before applying AI recommendations
* Escalation for safety, legal, and fraud-related cases

 Project Goal

The main goal is to demonstrate how Salesforce can combine:

Flow + Apex + Queueable Apex + REST Integration + Knowledge + LWC + AI + Security

to build a realistic customer service solution for a car rental company.


Author

Muthukumar S — Salesforce Developer
