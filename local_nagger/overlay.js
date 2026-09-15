// JXA (JavaScript for Automation) full-screen blurred reminder overlay.
// Run via: osascript -l JavaScript overlay.js "<item name>" "<giving_up_after_seconds>"
// Prints exactly one of: done | skip | timeout
//
// Implemented as JXA (not a plain Python/PyObjC NSApplication) because this
// process is what actually owns a live WindowServer connection reliably in
// this environment — a bare PyObjC NSApplication.run() invoked from a
// background-spawned Python process was observed to hang indefinitely with
// no window ever appearing, while `osascript -e 'display dialog ...'`
// (and therefore JXA, which runs inside the same osascript host process)
// reliably shows and dismisses windows.
ObjC.import("Cocoa");

function run(argv) {
  var name = argv[0] || "Reminder";
  var givingUpAfter = parseFloat(argv[1]);
  if (isNaN(givingUpAfter)) givingUpAfter = 50;

  var state = { value: "timeout", done: false };

  ObjC.registerSubclass({
    name: "LocalNaggerOverlayController",
    methods: {
      "onDone:": {
        types: ["void", ["id"]],
        implementation: function (sender) {
          state.value = "done";
          state.done = true;
        },
      },
      "onSkip:": {
        types: ["void", ["id"]],
        implementation: function (sender) {
          state.value = "skip";
          state.done = true;
        },
      },
    },
  });

  var controller = $.LocalNaggerOverlayController.alloc.init;

  var app = $.NSApplication.sharedApplication;
  app.setActivationPolicy($.NSApplicationActivationPolicyAccessory);

  var collectionBehavior =
    $.NSWindowCollectionBehaviorCanJoinAllSpaces |
    $.NSWindowCollectionBehaviorFullScreenAuxiliary |
    $.NSWindowCollectionBehaviorStationary;

  var windows = [];
  var screens = $.NSScreen.screens;
  var screenCount = screens.count;

  for (var i = 0; i < screenCount; i++) {
    var screen = screens.objectAtIndex(i);
    var frame = screen.frame;
    var w = frame.size.width;
    var h = frame.size.height;

    var window = $.NSWindow.alloc.initWithContentRectStyleMaskBackingDeferScreen(
      frame,
      $.NSWindowStyleMaskBorderless,
      $.NSBackingStoreBuffered,
      false,
      screen
    );
    window.level = $.NSScreenSaverWindowLevel;
    window.opaque = false;
    window.backgroundColor = $.NSColor.clearColor;
    window.collectionBehavior = collectionBehavior;
    window.releasedWhenClosed = false;

    var effect = $.NSVisualEffectView.alloc.initWithFrame($.NSMakeRect(0, 0, w, h));
    effect.material = $.NSVisualEffectMaterialFullScreenUI;
    effect.blendingMode = $.NSVisualEffectBlendingModeBehindWindow;
    effect.state = $.NSVisualEffectStateActive;
    window.contentView = effect;

    var label = $.NSTextField.alloc.initWithFrame($.NSMakeRect(0, h / 2 + 10, w, 70));
    label.stringValue = "Reminder: " + name;
    label.alignment = $.NSTextAlignmentCenter;
    label.font = $.NSFont.systemFontOfSize(40);
    label.bezeled = false;
    label.drawsBackground = false;
    label.editable = false;
    label.selectable = false;
    label.textColor = $.NSColor.whiteColor;
    effect.addSubview(label);

    // Buttons only need to be interactive on one screen (the user only has
    // one mouse cursor); the rest are decorative blur-only overlays so the
    // whole desktop is blocked no matter which screen is being looked at.
    if (i === 0) {
      var doneButton = $.NSButton.alloc.initWithFrame($.NSMakeRect(w / 2 - 170, h / 2 - 70, 150, 46));
      doneButton.title = "Done for today";
      doneButton.bezelStyle = $.NSBezelStyleRounded;
      doneButton.target = controller;
      doneButton.action = "onDone:";
      doneButton.keyEquivalent = "\r";
      effect.addSubview(doneButton);

      var skipButton = $.NSButton.alloc.initWithFrame($.NSMakeRect(w / 2 + 20, h / 2 - 70, 150, 46));
      skipButton.title = "Skip today";
      skipButton.bezelStyle = $.NSBezelStyleRounded;
      skipButton.target = controller;
      skipButton.action = "onSkip:";
      effect.addSubview(skipButton);
    }

    window.makeKeyAndOrderFront($());
    windows.push(window);
  }

  app.activateIgnoringOtherApps(true);

  var deadline = $.NSDate.dateWithTimeIntervalSinceNow(givingUpAfter);
  while (!state.done && deadline.timeIntervalSinceNow > 0) {
    var untilDate = $.NSDate.dateWithTimeIntervalSinceNow(0.15);
    var event = app.nextEventMatchingMaskUntilDateInModeDequeue(
      $.NSUIntegerMax,
      untilDate,
      $.NSDefaultRunLoopMode,
      true
    );
    if (!event.isNil()) app.sendEvent(event);
  }

  windows.forEach(function (w) {
    w.orderOut($());
  });

  return state.value;
}
