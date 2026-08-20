@IsTest
private class WorkflowCheckTest {
    @IsTest
    static void workflowCheckPasses() {
        System.assertEquals(1, 1);
    }
}

// GitHub Actions 재실행 확인용