#import "command_execution_test_bridge.h"
static NSMutableArray<NSString *> *events;
static NSString *session;
void CommandTestReset(void) { events = [NSMutableArray array]; session = @"old"; }
void CommandTestSetSession(NSString *value) { session = [value copy]; }
NSArray<NSString *> *CommandTestEvents(void) { return [events copy]; }
int LiSendKeyboardEvent(short key, char action, char modifiers) {
    NSCAssert(NSThread.isMainThread, @"shortcut delivery must stay serialized with teardown");
    [events addObject:[NSString stringWithFormat:@"%@:K%d:%@", session, key, action == KEY_ACTION_DOWN ? @"down" : @"up"]];
    return 0;
}
int LiSendMouseButtonEvent(char action, int button) {
    NSCAssert(NSThread.isMainThread, @"shortcut delivery must stay serialized with teardown");
    [events addObject:[NSString stringWithFormat:@"%@:M%d:%@", session, button, action == BUTTON_ACTION_PRESS ? @"down" : @"up"]];
    return 0;
}
