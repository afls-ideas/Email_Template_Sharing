/**
 * DEMO_EmailTmplGroupSharing
 *
 * Trigger on LifeSciEmailTemplate that shares email templates (and their
 * related fragments) with a Public Group specified in the custom field
 * ShareWithGroupId__c.
 *
 * Fires on before delete (to capture fragment IDs before junction records
 * cascade-delete) and after insert, update, delete to manage share records.
 */
trigger DEMO_EmailTmplGroupSharing on LifeSciEmailTemplate (before delete, after insert, after update, after delete) {

    DEMO_EmailTmplGroupSharingHandler handler = new DEMO_EmailTmplGroupSharingHandler();

    if (Trigger.isBefore && Trigger.isDelete) {
        // Before delete: capture fragment IDs now, because the junction object
        // (LifeSciEmailTmplRelaFrgmt) is ControlledByParent and will be
        // cascade-deleted before the after delete trigger fires
        handler.cacheFragmentIdsForDelete(Trigger.old);
    }

    if (Trigger.isAfter) {

        if (Trigger.isInsert) {
            // New templates: create share records for any that have a group assigned
            handler.handleAfterInsert(Trigger.new);

        } else if (Trigger.isUpdate) {
            // Updated templates: detect changes to ShareWithGroupId__c,
            // remove old shares and create new ones as needed
            handler.handleAfterUpdate(Trigger.new, Trigger.oldMap);

        } else if (Trigger.isDelete) {
            // Deleted templates: template shares cascade-delete automatically,
            // but fragment shares must be cleaned up using IDs cached in before delete
            handler.handleAfterDelete(Trigger.old);
        }
    }
}
