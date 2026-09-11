import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getCaseDetails from '@salesforce/apex/CaseAgentAssistController.getCaseDetails';
import refreshAIAssistance from '@salesforce/apex/CaseAgentAssistController.refreshAIAssistance';
import saveAgentAction from '@salesforce/apex/CaseAgentAssistController.saveAgentAction';
import syncBookingData from '@salesforce/apex/CaseAgentAssistController.syncBookingData';

export default class CaseAgentAssist extends LightningElement {
    @api recordId;

    @track isLoading = false;
    @track caseRecord = {};
    @track aiRec = {};
    @track recentInteractions = [];

    @track draftText = '';
    @track originalDraft = '';

    // Modal state for Reject / Escalate
    @track isModalOpen = false;
    @track modalTitle = '';
    @track modalDescription = '';
    @track modalActionType = ''; // 'Rejected' or 'Escalated'
    @track modalReason = '';

    connectedCallback() {
        if (this.recordId) {
            this.loadConsoleData();
        }
    }

    // ─── Data Loader ──────────────────────────────────────────────────────────
    loadConsoleData() {
        this.isLoading = true;
        getCaseDetails({ caseId: this.recordId })
            .then(result => {
                if (result) {
                    this.caseRecord = result.caseRecord || {};
                    this.aiRec = result.aiRecommendation || {};
                    this.recentInteractions = this.formatInteractions(result.recentInteractions || []);

                    this.draftText = this.aiRec.suggestedResponse || '';
                    this.originalDraft = this.draftText;
                }
            })
            .catch(error => {
                this.showToast('Error Loading Console', this.extractErrorMessage(error), 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    // ─── Event Handlers: AI & Booking Actions ─────────────────────────────────
    handleRefresh() {
        this.loadConsoleData();
    }

    handleSyncBooking() {
        this.isLoading = true;
        syncBookingData({ caseId: this.recordId })
            .then(() => {
                this.showToast('Booking Sync Requested', 'Asynchronous lookup has been queued.', 'info');
                // Poll/refresh after brief delay
                setTimeout(() => {
                    this.loadConsoleData();
                }, 1500);
            })
            .catch(error => {
                this.showToast('Sync Failed', this.extractErrorMessage(error), 'error');
                this.isLoading = false;
            });
    }

    handleDraftChange(event) {
        this.draftText = event.target.value;
    }

    handleApprove() {
        this.executeAgentAction('Accepted', this.draftText, 'Draft approved as recommended');
    }

    handleSaveEdits() {
        this.executeAgentAction('Edited', this.draftText, 'Agent edited draft response before sending');
    }

    // ─── Modal Workflows (Reject & Escalate) ───────────────────────────────────
    openRejectModal() {
        this.modalActionType = 'Rejected';
        this.modalTitle = 'Reject AI Draft Recommendation';
        this.modalDescription = 'Please document why this AI suggestion was rejected for compliance review:';
        this.modalReason = '';
        this.isModalOpen = true;
    }

    openEscalateModal() {
        this.modalActionType = 'Escalated';
        this.modalTitle = 'Escalate Case to Specialist';
        this.modalDescription = 'Please specify the reason for supervisory escalation:';
        this.modalReason = this.aiRec.restrictionReason || '';
        this.isModalOpen = true;
    }

    closeModal() {
        this.isModalOpen = false;
        this.modalReason = '';
    }

    handleModalReasonChange(event) {
        this.modalReason = event.target.value;
    }

    handleConfirmModalAction() {
        if (!this.modalReason || this.modalReason.trim() === '') {
            this.showToast('Validation Error', 'A reason is required to record this action.', 'warning');
            return;
        }

        const action = this.modalActionType;
        const reason = this.modalReason;
        this.closeModal();

        this.executeAgentAction(action, this.draftText, reason);
    }

    // ─── Action Execution Core ────────────────────────────────────────────────
    executeAgentAction(agentAction, finalResponse, overrideReason) {
        this.isLoading = true;

        saveAgentAction({
            caseId: this.recordId,
            agentAction: agentAction,
            responseText: finalResponse,
            overrideReason: overrideReason,
            confidenceScore: this.aiRec.confidenceScore,
            groundedStatus: this.aiRec.groundedStatus
        })
            .then(() => {
                this.showToast('Action Recorded', `AI suggestion successfully marked as ${agentAction}.`, 'success');
                this.loadConsoleData();
            })
            .catch(error => {
                this.showToast('Error Saving Action', this.extractErrorMessage(error), 'error');
                this.isLoading = false;
            });
    }

    // ─── Getters & Dynamic Formatting ─────────────────────────────────────────
    get currentAssistanceStatus() {
        return this.caseRecord.AI_Assistance_Status__c || this.aiRec.assistanceStatus || 'Pending';
    }

    get statusBadgeClass() {
        const s = (this.currentAssistanceStatus || '').toLowerCase();
        return `status-pill status-${s}`;
    }

    get bookingReference() {
        return this.caseRecord.Booking_Reference__c || 'None';
    }

    get bookingStatus() {
        return this.caseRecord.Booking_Status__c || 'Not Synced';
    }

    get bookingStatusBadgeClass() {
        const s = (this.bookingStatus || '').toLowerCase();
        if (s.includes('confirm')) return 'status-pill status-approved';
        if (s.includes('fail') || s.includes('cancel')) return 'status-pill status-restricted';
        return 'status-pill status-pending';
    }

    get supplierName() {
        return this.caseRecord.Supplier_Name__c || '—';
    }

    get vehicleClass() {
        return this.caseRecord.Vehicle_Class__c || '—';
    }

    get pickupLocation() {
        return this.caseRecord.Pickup_Location__c || '—';
    }

    get intentBadgeClass() {
        return 'intent-badge';
    }

    get urgencyBadgeClass() {
        const u = (this.aiRec.urgency || '').toLowerCase();
        return `urgency-badge urgency-${u}`;
    }

    get confidencePercentage() {
        if (this.aiRec.confidenceScore != null) {
            return (this.aiRec.confidenceScore * 100).toFixed(0);
        }
        return '0';
    }

    get confidenceBarStyle() {
        return `width: ${this.confidencePercentage}%`;
    }

    get draftCharCount() {
        return this.draftText ? this.draftText.length : 0;
    }

    get draftWordCount() {
        if (!this.draftText || this.draftText.trim() === '') return 0;
        return this.draftText.trim().split(/\s+/).length;
    }

    get isSaveEditsDisabled() {
        return this.isLoading || (this.draftText === this.originalDraft);
    }

    get isModalConfirmDisabled() {
        return this.isLoading || !this.modalReason || this.modalReason.trim() === '';
    }

    get hasRecentInteractions() {
        return this.recentInteractions && this.recentInteractions.length > 0;
    }

    formatInteractions(list) {
        return list.map(item => {
            const act = (item.Agent_Action__c || 'Pending').toLowerCase();
            return {
                ...item,
                confidenceFormatted: item.Confidence_Score__c ? (item.Confidence_Score__c * 100).toFixed(0) : '0',
                actionClass: `status-pill status-${act}`,
                groundedIcon: item.Grounded_Status__c ? 'utility:check' : 'utility:close',
                groundedVariant: item.Grounded_Status__c ? 'success' : 'error'
            };
        });
    }

    // ─── Toast & Error Helpers ────────────────────────────────────────────────
    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    extractErrorMessage(error) {
        if (error && error.body && error.body.message) {
            return error.body.message;
        }
        return JSON.stringify(error);
    }
}
