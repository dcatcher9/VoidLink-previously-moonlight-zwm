#import "HttpResponse.h"
#include <stdio.h>
#include <stdlib.h>

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

int main(void) {
    @autoreleasepool {
        TestUInt64();
        TestStatuses();
        printf("HttpResponse: %u assertions passed\n", assertions);
    }
    return 0;
}
