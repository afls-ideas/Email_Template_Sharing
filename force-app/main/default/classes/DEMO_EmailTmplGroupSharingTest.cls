@IsTest
private class DEMO_EmailTmplGroupSharingTest {

    /**
     * Helper: create a public group for testing.
     */
    private static Group createPublicGroup(String name, String devName) {
        Group g = new Group(Name = name, DeveloperName = devName, Type = 'Regular');
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
        Group publicGroup = createPublicGroup('Test Email Group', 'Test_Email_Group');

        Test.startTest();
        LifeSciEmailTemplate tmpl = createTemplate('Test Template', 'Test_Email_Group');
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
        Group groupA = createPublicGroup('Group A', 'Group_A');
        Group groupB = createPublicGroup('Group B', 'Group_B');

        LifeSciEmailTemplate tmpl = createTemplate('Update Test', 'Group_A');
        insert tmpl;

        // Verify initial share
        List<LifeSciEmailTemplateShare> sharesA = [
            SELECT UserOrGroupId FROM LifeSciEmailTemplateShare
            WHERE ParentId = :tmpl.Id AND RowCause = 'Manual'
        ];
        System.assertEquals(1, sharesA.size());
        System.assertEquals(groupA.Id, sharesA[0].UserOrGroupId);

        // Change group developer name
        Test.startTest();
        tmpl.ShareWithGroupName__c = 'Group_B';
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
        Group publicGroup = createPublicGroup('Clear Test Group', 'Clear_Test_Group');

        LifeSciEmailTemplate tmpl = createTemplate('Clear Test', 'Clear_Test_Group');
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
        Group publicGroup = createPublicGroup('Fragment Test Group', 'Fragment_Test_Group');

        // Create template without group first so we can add a fragment
        LifeSciEmailTemplate tmpl = createTemplate('Fragment Test', null);
        insert tmpl;

        LifeSciEmailTmplFragment frag = createFragmentForTemplate(tmpl.Id);

        // Now set the group developer name to trigger sharing
        Test.startTest();
        tmpl.ShareWithGroupName__c = 'Fragment_Test_Group';
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
        Group publicGroup = createPublicGroup('Delete Test Group', 'Delete_Test_Group');

        LifeSciEmailTemplate tmpl = createTemplate('Delete Test', null);
        insert tmpl;

        LifeSciEmailTmplFragment frag = createFragmentForTemplate(tmpl.Id);

        // Set group developer name to create shares
        tmpl.ShareWithGroupName__c = 'Delete_Test_Group';
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
        LifeSciEmailTemplate tmpl = createTemplate('Bad Group Test', 'Nonexistent_Group_XYZ');
        insert tmpl;
        Test.stopTest();

        List<LifeSciEmailTemplateShare> shares = [
            SELECT Id FROM LifeSciEmailTemplateShare
            WHERE ParentId = :tmpl.Id AND RowCause = 'Manual'
        ];
        System.assertEquals(0, shares.size(), 'Expected no shares for invalid group name');
    }
}
