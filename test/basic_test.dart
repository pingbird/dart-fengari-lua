@TestOn("browser")
import "package:test/test.dart";
import 'package:fengari_lua/lua.dart';
import 'dart:developer';

void main() {
  test("Simple stack manipulation", () {
    var state = LuaState();

    state.push(123);
    expect(state.popValue(), equals(123));
    expect(state.top, equals(0));

    state.pushAll(["a", "s", "d", "f"]);
    expect(state.popValues(4), equals(["a", "s", "d", "f"]));
    expect(state.top, equals(0));

    state.pushAll([1, 2, 3, 4]);
    expect(state.values(4), equals([1, 2, 3, 4]));
    expect(state.values(3, -4), equals([1, 2, 3]));
    state.pop(4);
    expect(state.top, equals(0));

    state.pushAll([1, 2, 3, 4]);
    state.remove(-2);
    expect(state.popValues(3), equals([1, 2, 4]));
    expect(state.top, equals(0));
  });

  test("Simple loadstring and call", () {
    var state = LuaState();
    state.loadString('return "Hello, World!"');
    expect(state.call(), equals(["Hello, World!"]));
    state.close();
  });

  test("Vararg calls and results", () {
    var state = LuaState();
    state.loadString('return ...');

    final list = [];
    for (var i = 0; i < 2; i++) {
      list.add(i * i);
      state.dup();
      expect(state.call(list), equals(list));
    }

    expect(state.top, equals(1));
    state.close();
  });

  test("Calling LuaCFunction", () {
    var state = LuaState();

    state.loadString('''
      local f = ...
      return f("Hello!", 1, 2, 3)
    ''');

    expect(state.call([(LuaState state) {
      expect(state.top, equals(4));
      state.push(state[1]);
      state.push(state[2] + state[3] + state[4]);
      return 2;
    }]), equals(["Hello!", 6]));

    debugger();
    expect(state.top, equals(0));
    state.close();
  });

  test("Calling LuaFunction", () {
    var state = LuaState();

    state.loadString('''
      local f = ...
      return f("Hello!", 1, 2, 3)
    ''');

    expect(state.call([(LuaState state, List args) {
      expect(args.length, equals(4));
      return [
        args[0],
        args[1] + args[2] + args[3]
      ];
    }]), equals(["Hello!", 6]));

    expect(state.top, equals(0));
    state.close();
  });

  test("Rotate stack", () {
    var state = LuaState();

    state.pushAll(["a", "b", "c", "d"]);
    state.rotate(-4, 1);
    expect(state.values(4), equals(["d", "a", "b", "c"]));
    state.rotate(-4, -3);
    expect(state.values(4), equals(["c", "d", "a", "b"]));

    state.close();
  });

  test("Manual openlibs libraries", () {
    var state = LuaState(openlibs: false);

    state.pushGlobal("string");
    expect(state.isNil(), isTrue);
    state.pop();

    state.requiref("string", luaStringLib);

    state.pushGlobal("string");
    expect(state.isTable(), isTrue);
    state.pop();

    state.close();
  });
}