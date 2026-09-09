#import "HttpResponse.h"
#import "AppListResponse.h"
#import "TemporaryApp.h"

@implementation TemporaryApp @end
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static unsigned int assertions;

static void Check(BOOL condition, NSString* description) {
    assertions++;
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", description.UTF8String);
        exit(1);
    }
}

static void Populate(HttpResponse* response, NSString* xml) {
    [response populateWithData:[xml dataUsingEncoding:NSUTF8StringEncoding]];
}

static HttpResponse* ResponseForValue(NSString* value) {
    HttpResponse* response = [[HttpResponse alloc] init];
    Populate(response, [NSString stringWithFormat:@"<root status_code=\"200\" status_message=\"OK\"><hostsessionid>%@</hostsessionid></root>", value]);
    return response;
}

static void TestUInt64(void) {
    NSArray<NSString*>* accepted = @[@"0", @"42", @" \n\t42 \n", @"00042", @"9223372036854775808", @"18446744073709551615"];
    uint64_t expected[] = {0, 42, 42, 42, UINT64_C(9223372036854775808), UINT64_MAX};
    for (NSUInteger i = 0; i < accepted.count; i++) {
        HttpResponse* response = ResponseForValue(accepted[i]);
        uint64_t value = 123;
        Check([response getUInt64Tag:@"hostsessionid" value:&value], [@"Accept unsigned value: " stringByAppendingString:accepted[i]]);
        Check(value == expected[i], @"Preserve exact uint64 value");
    }

    NSArray<NSString*>* rejected = @[@"", @" \n\t", @"-1", @"+1", @"1x", @"1 2", @"1.0", @"0x10", @"１２", @"18446744073709551616", @"999999999999999999999999999999999999999"];
    for (NSString* text in rejected) {
        HttpResponse* response = ResponseForValue(text);
        uint64_t value = 123;
        Check(![response getUInt64Tag:@"hostsessionid" value:&value], [@"Reject invalid unsigned value: " stringByAppendingString:text]);
        Check(value == 123, @"Failure leaves output unchanged");
    }

    HttpResponse* response = ResponseForValue(@"7");
    uint64_t value = 123;
    Check(![response getUInt64Tag:@"missing" value:&value], @"Reject absent tag");
    Check(value == 123, @"Absent tag leaves output unchanged");
    Check(![response getUInt64Tag:@"hostsessionid" value:NULL], @"Reject null output pointer");
}

static void TestStatuses(void) {
    HttpResponse* response = [[HttpResponse alloc] init];
    Check(!response.isStatusOk && response.statusMessage.length > 0, @"New responses default to meaningful failure");

    NSArray<NSString*>* malformed = @[@"", @" ", @"not xml", @"<root", @"<?xml version=\"1.0\"?><!-- no root -->", @"<root/>", @"<root status_code=\"\"/>", @"<root status_code=\"abc\"/>", @"<root status_code=\"200junk\"/>", @"<root status_code=\"18446744073709551616\"/>"];
    for (NSString* xml in malformed) {
        Populate(response, @"<root status_code=\"200\" status_message=\"Success\"><hostsessionid>7</hostsessionid></root>");
        Check(response.isStatusOk, @"Prepare successful reusable response");
        Populate(response, xml);
        Check(response.statusCode == 502, @"Malformed response resets previous success");
        Check(response.statusMessage.length > 0 && ![response.statusMessage isEqualToString:@"Success"], @"Malformed response supplies a fresh diagnostic");
        Check([response getStringTag:@"hostsessionid"] == nil, @"Malformed response clears old extension values");
    }
    [response populateWithData:nil];
    Check(response.statusCode == 502 && [response.statusMessage containsString:@"Empty"], @"Nil data produces empty-response error");

    Populate(response, @"<root status_code=\"409\" status_message=\"Session changed &amp; expired\"><hostsessionid>18446744073709551615</hostsessionid><empty/></root>");
    Check(response.statusCode == 409, @"Preserve valid failure status");
    Check([response.statusMessage isEqualToString:@"Session changed & expired"], @"Preserve and decode host message");
    Check([[response getStringTag:@"empty"] isEqualToString:@""], @"Preserve empty extension tag");
    Check([response getStringTag:@"absent"] == nil, @"Distinguish absent extension tag");
    uint64_t value;
    Check([response getUInt64Tag:@"hostsessionid" value:&value] && value == UINT64_MAX, @"Parse extension even for non-success status");

    Populate(response, @"<root status_code=\"-1\" status_message=\"Invalid\"/>");
    Check(response.statusCode == 418 && [response.statusMessage containsString:@"audio capture"], @"Preserve legacy audio error translation");
    Populate(response, @"<root status_code=\"200\"/>");
    Check(response.isStatusOk && [response.statusMessage isEqualToString:@"OK"], @"Successful response without message remains successful");
    Populate(response, @"<root status_code=\"500\" status_message=\" \"/>");
    Check(response.statusCode == 500 && [response.statusMessage containsString:@"500"], @"Blank host error message has useful fallback");
}

static void TestAppListRefresh(void) {
    AppListResponse *response = [AppListResponse new];
    Check(!response.isStatusOk, @"New app list starts as an explicit failure");
    NSString *valid = @"<root status_code=\"200\"><App><AppTitle>Desktop &amp; Tools</AppTitle><ID>123</ID><IsHdrSupported>1</IsHdrSupported><AppInstallPath>fixture</AppInstallPath></App></root>";
    for (NSString *invalid in @[@"", @"<root", @"<root/>", @"<root status_code=\"200x\"/>",
        @"<!DOCTYPE root [<!ENTITY name 'unsafe'>]><root status_code=\"200\"><App><ID>1</ID><AppTitle>&name;</AppTitle></App></root>"]) {
        [response populateWithData:[valid dataUsingEncoding:NSUTF8StringEncoding]];
        TemporaryApp *app = response.getAppList.anyObject;
        Check(response.isStatusOk && response.getAppList.count == 1 && [app.id isEqual:@"123"] &&
              [app.name isEqual:@"Desktop & Tools"] && app.hdrSupported && [app.installPath isEqual:@"fixture"],
              @"Valid app list retains ID, decoded name, HDR and install-path metadata");
        [response populateWithData:[invalid dataUsingEncoding:NSUTF8StringEncoding]];
        Check(response.statusCode == 502 && response.getAppList.count == 0 && response.statusMessage.length > 0,
              @"Malformed refresh clears apps and cannot reuse a previous successful status");
    }
    [response populateWithData:[@"<root status_code=\"401\" status_message=\"Pair again\"><App><ID>1</ID></App></root>" dataUsingEncoding:NSUTF8StringEncoding]];
    Check(response.statusCode == 401 && [response.statusMessage isEqual:@"Pair again"] && response.getAppList.count == 0,
          @"Failed app-list status preserves host error without exposing unusable entries");
}

static void TestPrivateDiagnostics(void) {
    HttpResponse *response = [HttpResponse new];
    FILE *capture = tmpfile();
    Check(capture != NULL, @"Create isolated stderr capture");
    int previous = dup(STDERR_FILENO);
    Check(previous >= 0 && dup2(fileno(capture), STDERR_FILENO) >= 0, @"Capture parser diagnostics");
    Populate(response, @"<root status_code=\"200\"><pairingsecret>private-pairing-sentinel</wrong></root>");
    fflush(stderr);
    Check(dup2(previous, STDERR_FILENO) >= 0, @"Restore stderr"); close(previous);
    fseek(capture, 0, SEEK_END);
    Check(ftell(capture) == 0, @"Malformed XML diagnostics never echo host response secrets");
    fclose(capture);
    Check(!response.isStatusOk, @"Suppressing diagnostics does not accept malformed XML");
    for (NSString *xml in @[
        @"<!DOCTYPE root [<!ENTITY secret 'private-pairing-sentinel'>]><root status_code=\"200\"><value>&secret;</value></root>",
        @"<!DOCTYPE root SYSTEM 'https://fixture.invalid/private'><root status_code=\"200\"/>"]) {
        Populate(response, xml);
        Check(response.statusCode == 502 && [response getStringTag:@"value"] == nil, @"Reject unnecessary DTD/entity declarations before reading response fields");
    }
}

int main(void) {
    @autoreleasepool {
        TestUInt64();
        TestStatuses();
        TestPrivateDiagnostics();
        TestAppListRefresh();
        printf("HttpResponse: %u assertions passed\n", assertions);
    }
    return 0;
}
