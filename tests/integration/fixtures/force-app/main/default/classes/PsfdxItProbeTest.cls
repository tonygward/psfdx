@IsTest
private class PsfdxItProbeTest {
    @IsTest
    static void addsTwoNumbers() {
        System.assertEquals(3, PsfdxItProbe.add(1, 2));
    }
}
