/**
 * DEMO_EmailTmplGroupSharingHandler
 *
 * Handler class for DEMO_EmailTmplGroupSharing trigger.
 * Manages LifeSciEmailTemplateShare and LifeSciEmailTmplFragmentShare records
 * based on the ShareWithGroupName__c field on LifeSciEmailTemplate.
 *
 * The field stores a Public Group name (user-friendly). The handler resolves
 * the name to a Group ID at runtime via SOQL lookup.
 *
 * Sharing approach:
 *   - Template shares use RowCause = 'Manual' with AccessLevel = 'Read'
 *   - Fragment shares are created for all fragments linked via LifeSciEmailTmplRelaFrgmt
 *   - Database.insert/delete with allOrNone=false to handle partial failures gracefully
 */
public with sharing class DEMO_EmailTmplGroupSharingHandler {

    private static final String ROW_CAUSE = 'Manual';
    private static final String ACCESS_LEVEL = 'Read';

    // Static cache: fragment IDs captured in before delete, used in after delete.
    // Needed because LifeSciEmailTmplRelaFrgmt is ControlledByParent and gets
    // cascade-deleted before the after delete trigger fires.
    private static Set<Id> cachedFragmentIdsForDelete = new Set<Id>();

    /**
     * Before Delete: query and cache fragment IDs linked to templates being deleted.
     * Must run before cascade-delete removes the junction records.
     */
    public void cacheFragmentIdsForDelete(List<LifeSciEmailTemplate> oldRecords) {
        Set<Id> templateIds = new Set<Id>();
        for (LifeSciEmailTemplate tmpl : oldRecords) {
            if (String.isNotBlank(tmpl.ShareWithGroupName__c)) {
                templateIds.add(tmpl.Id);
            }
        }
        if (!templateIds.isEmpty()) {
            for (LifeSciEmailTmplRelaFrgmt junction : [
                SELECT LifeSciEmailTmplFragmentId
                FROM LifeSciEmailTmplRelaFrgmt
                WHERE LifeSciEmailTemplateId IN :templateIds
            ]) {
                cachedFragmentIdsForDelete.add(junction.LifeSciEmailTmplFragmentId);
            }
        }
    }

    /**
     * After Insert: create share records for templates that have a group assigned.
     */
    public void handleAfterInsert(List<LifeSciEmailTemplate> newRecords) {
        List<LifeSciEmailTemplate> templatesWithGroup = new List<LifeSciEmailTemplate>();
        for (LifeSciEmailTemplate tmpl : newRecords) {
            if (String.isNotBlank(tmpl.ShareWithGroupName__c)) {
                templatesWithGroup.add(tmpl);
            }
        }
        if (!templatesWithGroup.isEmpty()) {
            createShares(templatesWithGroup);
        }
    }

    /**
     * After Update: detect changes to ShareWithGroupName__c.
     * - If the old value was populated, remove shares for the old group.
     * - If the new value is populated, create shares for the new group.
     */
    public void handleAfterUpdate(List<LifeSciEmailTemplate> newRecords, Map<Id, LifeSciEmailTemplate> oldMap) {
        List<LifeSciEmailTemplate> templatesToShare = new List<LifeSciEmailTemplate>();
        Set<Id> templatesToRemoveShares = new Set<Id>();

        for (LifeSciEmailTemplate tmpl : newRecords) {
            String oldGroupName = oldMap.get(tmpl.Id).ShareWithGroupName__c;
            String newGroupName = tmpl.ShareWithGroupName__c;

            // Skip if field unchanged
            if (oldGroupName == newGroupName) {
                continue;
            }

            // Old group needs share removal
            if (String.isNotBlank(oldGroupName)) {
                templatesToRemoveShares.add(tmpl.Id);
            }

            // New group needs share creation
            if (String.isNotBlank(newGroupName)) {
                templatesToShare.add(tmpl);
            }
        }

        if (!templatesToRemoveShares.isEmpty()) {
            deleteShares(templatesToRemoveShares);
        }
        if (!templatesToShare.isEmpty()) {
            createShares(templatesToShare);
        }
    }

    /**
     * After Delete: clean up fragment shares for deleted templates.
     * Template shares cascade-delete automatically, but fragment shares
     * belong to the fragment (a separate top-level object), so we must
     * remove them explicitly. Uses fragment IDs cached in before delete.
     */
    public void handleAfterDelete(List<LifeSciEmailTemplate> oldRecords) {
        if (!cachedFragmentIdsForDelete.isEmpty()) {
            deleteFragmentSharesByFragmentIds(cachedFragmentIdsForDelete);
            cachedFragmentIdsForDelete.clear();
        }
    }

    /**
     * Resolves Public Group developer names to their IDs.
     * Returns a Map of DeveloperName -> Group Id.
     * Only matches groups with Type = 'Regular' (Public Groups).
     */
    private Map<String, Id> resolveGroupNames(Set<String> groupNames) {
        Map<String, Id> nameToId = new Map<String, Id>();
        for (Group g : [
            SELECT Id, DeveloperName FROM Group
            WHERE DeveloperName IN :groupNames AND Type = 'Regular'
        ]) {
            nameToId.put(g.DeveloperName, g.Id);
        }
        return nameToId;
    }

    /**
     * Creates LifeSciEmailTemplateShare and LifeSciEmailTmplFragmentShare
     * records for the given templates based on their ShareWithGroupName__c value.
     * Looks up the group name to resolve to a Group ID before creating shares.
     */
    private void createShares(List<LifeSciEmailTemplate> templates) {
        // Collect all group names to resolve in a single query
        Set<String> groupNames = new Set<String>();
        for (LifeSciEmailTemplate tmpl : templates) {
            groupNames.add(tmpl.ShareWithGroupName__c);
        }

        // Resolve names to IDs
        Map<String, Id> nameToId = resolveGroupNames(groupNames);

        List<LifeSciEmailTemplateShare> templateShares = new List<LifeSciEmailTemplateShare>();
        Set<Id> templateIds = new Set<Id>();
        Map<Id, Id> templateToGroupId = new Map<Id, Id>();

        for (LifeSciEmailTemplate tmpl : templates) {
            Id groupId = nameToId.get(tmpl.ShareWithGroupName__c);

            // Skip if group name didn't resolve (typo, deleted group, etc.)
            if (groupId == null) {
                continue;
            }

            templateIds.add(tmpl.Id);
            templateToGroupId.put(tmpl.Id, groupId);

            // Create one share record per template -> group
            LifeSciEmailTemplateShare share = new LifeSciEmailTemplateShare();
            share.ParentId = tmpl.Id;
            share.UserOrGroupId = groupId;
            share.AccessLevel = ACCESS_LEVEL;
            share.RowCause = ROW_CAUSE;
            templateShares.add(share);
        }

        // Query the junction object to find all fragments used by these templates
        List<LifeSciEmailTmplRelaFrgmt> junctions = [
            SELECT LifeSciEmailTemplateId, LifeSciEmailTmplFragmentId
            FROM LifeSciEmailTmplRelaFrgmt
            WHERE LifeSciEmailTemplateId IN :templateIds
        ];

        // Build fragment share records, deduplicating by fragment+group
        List<LifeSciEmailTmplFragmentShare> fragmentShares = new List<LifeSciEmailTmplFragmentShare>();
        Set<String> fragmentShareKeys = new Set<String>();

        for (LifeSciEmailTmplRelaFrgmt junction : junctions) {
            Id groupId = templateToGroupId.get(junction.LifeSciEmailTemplateId);
            String dedupeKey = junction.LifeSciEmailTmplFragmentId + ':' + groupId;

            // Multiple templates may reference the same fragment — only share once per group
            if (fragmentShareKeys.contains(dedupeKey)) {
                continue;
            }
            fragmentShareKeys.add(dedupeKey);

            LifeSciEmailTmplFragmentShare fShare = new LifeSciEmailTmplFragmentShare();
            fShare.ParentId = junction.LifeSciEmailTmplFragmentId;
            fShare.UserOrGroupId = groupId;
            fShare.AccessLevel = ACCESS_LEVEL;
            fShare.RowCause = ROW_CAUSE;
            fragmentShares.add(fShare);
        }

        // Use allOrNone=false so one bad record doesn't block everything
        if (!templateShares.isEmpty()) {
            Database.insert(templateShares, false);
        }
        if (!fragmentShares.isEmpty()) {
            Database.insert(fragmentShares, false);
        }
    }

    /**
     * Deletes Manual-cause template shares and related fragment shares
     * for the given template IDs.
     */
    private void deleteShares(Set<Id> templateIds) {
        // Remove template-level shares created by this trigger
        List<LifeSciEmailTemplateShare> existingShares = [
            SELECT Id FROM LifeSciEmailTemplateShare
            WHERE ParentId IN :templateIds
            AND RowCause = :ROW_CAUSE
        ];
        if (!existingShares.isEmpty()) {
            Database.delete(existingShares, false);
        }

        // Remove fragment-level shares for fragments linked to these templates
        deleteFragmentSharesForTemplates(templateIds);
    }

    /**
     * Removes Manual-cause fragment shares for fragments that are related
     * to the given template IDs via LifeSciEmailTmplRelaFrgmt.
     */
    private void deleteFragmentSharesForTemplates(Set<Id> templateIds) {
        List<LifeSciEmailTmplRelaFrgmt> junctions = [
            SELECT LifeSciEmailTmplFragmentId
            FROM LifeSciEmailTmplRelaFrgmt
            WHERE LifeSciEmailTemplateId IN :templateIds
        ];

        Set<Id> fragmentIds = new Set<Id>();
        for (LifeSciEmailTmplRelaFrgmt junction : junctions) {
            fragmentIds.add(junction.LifeSciEmailTmplFragmentId);
        }

        deleteFragmentSharesByFragmentIds(fragmentIds);
    }

    /**
     * Removes Manual-cause fragment shares for the given fragment IDs.
     * Used by both update (via deleteFragmentSharesForTemplates) and
     * delete (via cached IDs from before delete).
     */
    private void deleteFragmentSharesByFragmentIds(Set<Id> fragmentIds) {
        if (!fragmentIds.isEmpty()) {
            List<LifeSciEmailTmplFragmentShare> fragmentShares = [
                SELECT Id FROM LifeSciEmailTmplFragmentShare
                WHERE ParentId IN :fragmentIds
                AND RowCause = :ROW_CAUSE
            ];
            if (!fragmentShares.isEmpty()) {
                Database.delete(fragmentShares, false);
            }
        }
    }
}
