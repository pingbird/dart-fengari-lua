# fengari-lua: Dart bindings for fengari-web, a Lua 5.3 interpreter.

## Installation

1. Add the following package to your pubspec:

```yaml
dependencies:
  fengari_lua:
    git: git@github.com:PixelToast/dart-fengari-lua.git
```

2. Add fengari-web.js to your html:

```html
<head>
    ...
    <script src="https://github.com/fengari-lua/fengari-web/releases/download/v0.1.4/fengari-web.js"></script>
</head>
```

## Usage

This library comes with bindings for most of the Lua API, see https://www.lua.org/manual/5.3/

It also includes a wrapper which greatly simplifies interaction with Lua states, Example:

```dart
import 'package:fengari_lua/lua.dart';
main() {
  var state = LuaState();
  state.loadString("""
    print("Hello, World!");
  """);
  state.call();
  state.close();
}
```