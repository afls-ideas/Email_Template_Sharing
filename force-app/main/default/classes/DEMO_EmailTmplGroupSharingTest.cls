@IsTest
private class DEMO_EmailTmplGroupSharingTest {

    /**
     * Helper: create a public group for testing.
     */
    private static Group createPublicGroup(String name) {
        Group g = new Group(Name = name, Type = 'Regular');
        insert g;
        return g;
    }

    /**
     * Helper: create a LifeSciEmailTemplate with required fields.
     */
    private static LifeSciEmailTemplate createTemplate(String name, String groupName) {
        LifeSciEmailTemplate tmpl = new LifeSciEmailTemplate(
            Name = name,
            IsSubjectLineEditable = false,
            CanAttachiCalendarFile = false,
            IsDefaultAutoEmailTemplate = false,
            EffectiveStartDate = Date.today(),
            ShouldIgnoreEmailConsent = false,
            IsActive = false,
            HasSendConsentAcknowledgement = false,
            CanSendPresentationLinks = false,
            ShareWithGroupName__c = groupName
        );
        return tmpl;
    }

    /**
     * Helper: create a fragment and link it to a template via the junction object.
     */
    private static LifeSciEmailTmplFragment createFragmentForTemplate(Id templateId) {
        LifeSciEmailTmplFragment frag = new LifeSciEmailTmplFragment(
            Name = 'Test Fragment',
            Description = 'Test fragment for sharing test'
        );
        insert frag;

        LifeSciEmailTmplRelaFrgmt junction = new LifeSciEmailTmplRelaFrgmt(
            LifeSciEmailTemplateId = templateId,
            LifeSciEmailTmplFragmentId = frag.Id
        );
        insert junction;

        return frag;
    }

    /**
     * Test: inserting a template with ShareWithGroupName__c populated
     * creates a LifeSciEmailTemplateShare record for that group.
     */
    @IsTest
    static void testInsertWithGroup_createsTemplateShare() {
        Group publicGroup = createPublicGroup('Test Email Group');

        Test.startTest();
        LifeSciEmailTemplate tmpl = createTemplate('Test Template', 'Test Email Group');
        insert tmpl;
        Test.stopTest();

        List<LifeSciEmailTemplateShare> shares = [
            SELECT Id, UserOrGroupId, AccessLevel, RowCause
            FROM LifeSciEmailTemplateShare
            WHERE ParentId = :tmpl.Id
            AND RowCause = 'Manual'
        ];

        System.assertEquals(1, shares.size(), 'Expected one Manual share record');
        System.assertEquals(publicGroup.Id, shares[0].UserOrGroupId);
        System.assertEquals('Read', shares[0].AccessLevel);
    }

    /**
     * Test: inserting a template without ShareWithGroupName__c
     * does NOT create any Manual share records.
     */
    @IsTest
    static void testInsertWithoutGroup_noShare() {
        Test.startTest();
        LifeSciEmailTemplate tmpl = createTemplate('No Group Template', null);
        insert tmpl;
        Test.stopTest();

        List<LifeSciEmailTemplateShare> shares = [
            SELECT Id FROM LifeSciEmailTemplateShare
            WHERE ParentId = :tmpl.Id
            AND RowCause = 'Manual'
        ];

        System.assertEquals(0, shares.size(), 'Expected no Manual share records');
    }

    /**
     * Test: updating a template to change the group name removes old shares
     * and creates new shares for the new group.
     */
    @IsTest
    static void testUpdateGroup_replacesShares() {
        Group groupA = createPublicGroup('Group A');
        Group groupB = createPublicGroup('Group B');

        LifeSciEmailTemplate tmpl = createTemplate('Update Test', 'Group A');
        insert tmpl;

        // Verify initial share
        List<LifeSciEmailTemplateShare> sharesA = [
            SELECT UserOrGroupId FROM LifeSciEmailTemplateShare
            WHERE ParentId = :tmpl.Id AND RowCause = 'Manual'
        ];
        System.assertEquals(1, sharesA.size());
        System.assertEquals(groupA.Id, sharesA[0].UserOrGroupId);

        // Change group name
        Test.startTest();
        tmpl.ShareWithGroupName__c = 'Group B';
        update tmpl;
        Test.stopTest();

        List<LifeSciEmailTemplateShare> sharesB = [
            SELECT UserOrGroupId FROM LifeSciEmailTemplateShare
            WHERE ParentId = :tmpl.Id AND RowCause = 'Manual'
        ];
        System.assertEquals(1, sharesB.size(), 'Expected one share after group change');
        System.assertEquals(groupB.Id, sharesB[0].UserOrGroupId);
    }

    /**
     * Test: clearing the group name field removes Manual shares.
     */
    @IsTest
    static void testClearGroup_removesShares() {
        Group publicGroup = createPublicGroup('Clear Test Group');

        LifeSciEmailTemplate tmpl = createTemplate('Clear Test', 'Clear Test Group');
        insert tmpl;

        Test.startTest();
        tmpl.ShareWithGroupName__c = null;
        update tmpl;
        Test.stopTest();

        List<LifeSciEmailTemplateShare> shares = [
            SELECT Id FROM LifeSciEmailTemplateShare
            WHERE ParentId = :tmpl.Id AND RowCause = 'Manual'
        ];
        System.assertEquals(0, shares.size(), 'Expected no Manual shares after clearing group');
    }

    /**
     * Test: fragments linked to a template also get shared when
     * ShareWithGroupName__c is populated.
     */
    @IsTest
    static void testFragmentSharing() {
        Group publicGroup = createPublicGroup('Fragment Test Group');

        // Create template without group first so we can add a fragment
        LifeSciEmailTemplate tmpl = createTemplate('Fragment Test', null);
        insert tmpl;

        LifeSciEmailTmplFragment frag = createFragmentForTemplate(tmpl.Id);

        // Now set the group name to trigger sharing
        Test.startTest();
        tmpl.ShareWithGroupName__c = 'Fragment Test Group';
        update tmpl;
        Test.stopTest();

        // Verify template share
        List<LifeSciEmailTemplateShare> tmplShares = [
            SELECT Id FROM LifeSciEmailTemplateShare
            WHERE ParentId = :tmpl.Id AND RowCause = 'Manual'
        ];
        System.assertEquals(1, tmplShares.size());

        // Verify fragment share
        List<LifeSciEmailTmplFragmentShare> fragShares = [
            SELECT Id, UserOrGroupId FROM LifeSciEmailTmplFragmentShare
            WHERE ParentId = :frag.Id AND RowCause = 'Manual'
        ];
        System.assertEquals(1, fragShares.size(), 'Expected fragment to be shared');
        System.assertEquals(publicGroup.Id, fragShares[0].UserOrGroupId);
    }

    /**
     * Test: deleting a template with ShareWithGroupName__c populated
     * cleans up fragment shares (template shares cascade-delete automatically).
     */
    @IsTest
    static void testDeleteTemplate_removesFragmentShares() {
        Group publicGroup = createPublicGroup('Delete Test Group');

        LifeSciEmailTemplate tmpl = createTemplate('Delete Test', null);
        insert tmpl;

        LifeSciEmailTmplFragment frag = createFragmentForTemplate(tmpl.Id);

        // Set group name to create shares
        tmpl.ShareWithGroupName__c = 'Delete Test Group';
        update tmpl;

        // Confirm fragment share exists before delete
        List<LifeSciEmailTmplFragmentShare> beforeShares = [
            SELECT Id FROM LifeSciEmailTmplFragmentShare
            WHERE ParentId = :frag.Id AND RowCause = 'Manual'
        ];
        System.assertEquals(1, beforeShares.size(), 'Fragment share should exist before delete');

        Test.startTest();
        delete tmpl;
        Test.stopTest();

        // Fragment share should be cleaned up by the trigger
        List<LifeSciEmailTmplFragmentShare> afterShares = [
            SELECT Id FROM LifeSciEmailTmplFragmentShare
            WHERE ParentId = :frag.Id AND RowCause = 'Manual'
        ];
        System.assertEquals(0, afterShares.size(), 'Fragment share should be removed after template delete');
    }

    /**
     * Test: inserting a template with an invalid group name
     * does NOT create any shares (graceful no-op).
     */
    @IsTest
    static void testInsertWithInvalidGroupName_noShare() {
        Test.startTest();
        LifeSciEmailTemplate tmpl = createTemplate('Bad Group Test', 'Nonexistent Group XYZ');
        insert tmpl;
        Test.stopTest();

        List<LifeSciEmailTemplateShare> shares = [
            SELECT Id FROM LifeSciEmailTemplateShare
            WHERE ParentId = :tmpl.Id AND RowCause = 'Manual'
        ];
        System.assertEquals(0, shares.size(), 'Expected no shares for invalid group name');
    }
}
