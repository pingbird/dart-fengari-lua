/// Library to make interacting with Lua states easier, see [LuaState].
library lua;
import 'dart:convert';
import 'dart:js';
import 'package:fengari_lua/fengari.dart';
import 'package:quiver/core.dart';

/// Lua base library, pass to [LuaState.requiref].
int luaBaseLib(LuaState state) => luaopen_base(state.L);

/// Lua coroutine library, pass to [LuaState.requiref].
int luaCoroutineLib(LuaState state) => luaopen_coroutine(state.L);

/// Lua debug library, pass to [LuaState.requiref].
int luaDebugLib(LuaState state) => luaopen_debug(state.L);

/// Lua fengari library, pass to [LuaState.requiref].
int luaFengariLib(LuaState state) => luaopen_fengari(state.L);

/// Lua math library, pass to [LuaState.requiref].
int luaMathLib(LuaState state) => luaopen_math(state.L);

/// Lua OS library, pass to [LuaState.requiref].
int luaOSLib(LuaState state) => luaopen_os(state.L);

/// Lua package library, pass to [LuaState.requiref].
int luaPackageLib(LuaState state) => luaopen_package(state.L);

/// Lua string library, pass to [LuaState.requiref].
int luaStringLib(LuaState state) => luaopen_string(state.L);

/// Lua table library, pass to [LuaState.requiref].
int luaTableLib(LuaState state) => luaopen_table(state.L);

/// Lua UTF8 library, pass to [LuaState.requiref].
int luaUTF8Lib(LuaState state) => luaopen_utf8(state.L);

/// Class for exceptions propagated from Lua, see [LuaState.load]
/// and [LuaState.call]
class LuaException {
  LuaException(this.message);

  final dynamic message;

  @override
  String toString() => '$message';
}

/// Opaque values for types that can't be converted to Dart values.
///
/// These do not represent the underlying value and are only valid for as long
/// as the value remains in the stack. You should not store these values
/// longer than that.
///
/// This is helpful for functions which want to take and return references to
/// values that cannot be referenced from dart, i.e. tables and functions.
///
/// Theoretically you could store actual references to these objects using
/// [lua_topointer] and peeking at the internal state of Fengari objects, but
/// this is undefined behavior and will break on a reference Lua implementation.
class LuaOpaqueValue {
  LuaOpaqueValue(this.type, this.name, this.index);
  int type;
  String name;
  int index;

  @override
  String toString() => name;

  @override
  int get hashCode => hash3(type, name, index);

  @override
  bool operator==(other) =>
    other is LuaOpaqueValue &&
    other.type == type &&
    other.name == name &&
    other.index == index;
}

/// The most basic function type that can be pushed, similar to `lua_CFunction`
/// in reference Lua.
///
/// To get the number of arguments use [LuaState.top] and access them using
/// [LuaState.at], Example:
///
///     state.push((LuaState fstate) {
///       // Sum all parameters
///       fstate.push(fstate.values(top).fold(0, (e, s) => e + s));
///       return 1; // Return 1 value
///     });
///
///     print(state.call([1234, 5678])); // Should print [6912]
///
/// Always push values to the state parameter instead of the state you push the
/// function to as the function can be called from a different state i.e.
/// inside of a coroutine.
typedef LuaCFunction = int Function(LuaState state);

/// More convenient version of LuaCFunction where arguments and returns are
/// dart iterables.
///
/// The same rules with manipulating state as [LuaCFunction] apply here.
typedef LuaFunction = Iterable Function(LuaState state, List args);

/// Wrapper class for simplifying interaction with Lua states,
///
/// [LuaState] does not contain any state information by itself and is
/// only a wrapper around the Fengari binding's [lua_State].
///
/// Please note that this wrapper makes many ease of use to performance
/// tradeoffs, interacting with the lua state directly through fengari_api
/// will be significantly more performant.
class LuaState {
  /// Internal Lua state.
  final lua_State L;

  /// Creates a new lua_State and wraps it.
  ///
  /// If [openlibs] is false then standard libraries such as math, string,
  /// table, etc will no longer be available as globals.
  LuaState({bool openlibs = true}) : L = luaL_newstate() {
    if (openlibs) luaL_openlibs(L);
    lua_atnativeerror(L, allowInterop((_) {
      // Log fatal errors to JS console, Fengari has poor internal
      // error management (catchall everywhere) so it isn't possible
      // to recover a lot of exceptions during calls themselves. :/

      (context["console"] as JsObject)
        .callMethod("error", [lua_touserdata(L, -1)]);
    }));
  }

  /// Wraps an existing Lua state.
  LuaState.wrap(lua_State lua_state) : L = lua_state;

  /// The index of the top value in the stack.
  ///
  /// Can be set to a previous value as a fast way to clean up or to fill
  /// in nil values.
  int get top => lua_gettop(L);
  set top(int index) => lua_settop(L, index);

  /// Pushes a new, empty table to the stack.
  void newTable() => lua_newtable(L);

  /// Pushes the global table (_G) to the stack.
  void pushGlobalTable() => lua_pushglobaltable(L);

  /// Pushes the current thread (coroutine) to the stack.
  void pushThread() => lua_pushthread(L);

  /// Pops [count] values from current [LuaState] and pushes them all onto
  /// the stack of the target [LuaState].
  void xmove(LuaState to, int count) => lua_xmove(L, to.L, count);

  /// Pops a key and value, then adds those to the table at [tableIndex].
  ///
  /// This does not pop the table, Example:
  ///
  ///     state.newTable();
  ///     state.push("myKey");
  ///     state.push("myValue");
  ///     state.tableSet();
  ///     // Top of stack is now: {myKey = "myValue"}
  ///
  /// If the table has a __newindex metamethod, this may invoke it, to avoid
  /// this behavior see [LuaState.tableSetRaw]
  void tableSet([int tableIndex = -3]) => lua_settable(L, tableIndex);

  /// Same as [LuaState.tableSet] but does not invoke any metamethods.
  void tableSetRaw([int tableIndex = -3]) => lua_rawset(L, tableIndex);

  /// Pops a key and pushes the value in the table at [tableIndex].
  ///
  /// This does not pop the table, Example:
  ///
  ///     // Assuming the top of the stack is {myKey = "myValue"}
  ///     state.push("myKey");
  ///     state.tableGet();
  ///     // Top of stack is now "myValue", with the input table behind it.
  ///
  /// If the table has a __index metamethod, this may invoke it, to avoid
  /// this behavior see [LuaState.tableGetRaw]
  void tableGet([int tableIndex = -2]) => lua_gettable(L, tableIndex);

  /// Same as [LuaState.tableGet] but does not invoke any metamethods.
  void tableGetRaw([int tableIndex = -2]) => lua_rawget(L, tableIndex);

  /// Pops a table from the stack and sets it as the metatable for
  /// the value at [index]
  void tableSetMeta([int index = -2]) => lua_setmetatable(L, index);

  /// Pushes the global variable from a [key] to the stack.
  ///
  /// This is equivalent to:
  ///
  ///     state.pushGlobalTable();
  ///     state.push(key);
  ///     state.tableGet();
  ///     state.remove(-2);
  ///
  void pushGlobal(dynamic key) {
    lua_pushglobaltable(L);
    push(key);
    tableGet();
    remove(-2);
  }

  /// Pops a value from the stack and sets the global at [key] to it.
  ///
  /// This is equivalent to:
  ///
  ///     state.pushGlobalTable();
  ///     state.push(key);
  ///     state.dup(-3); // Get value from what was previously top of stack
  ///     state.tableSet();
  ///     state.pop(2); // Pop both the global table and original value
  ///
  void setGlobal(dynamic key) {
    pushGlobalTable();
    push(key);
    dup(-3);
    tableSet();
    pop(2);
  }

  /// Removes a value in the stack at a specific index,
  /// shifting values above it down to fill the gap.
  void remove(int index) => lua_remove(L, index);

  /// Pushes the value at [index].
  void dup([int index = -1]) => lua_pushvalue(L, index);

  /// Returns the stack value at [index] and converts it to the
  /// equivalent Dart type.
  ///
  /// Because of a limitation of Lua, functions and tables cannot be represented
  /// in Dart without a deep copy, these values are instead returned as an
  /// [LuaOpaqueValue] which references the stack position it was found in.
  dynamic at([int index = -1]) {
    assert(index != 0, "Index must not be 0");
    assert(index <= top, "Index overflowed stack");
    assert(index >= -top, "Index overflowed stack");
    if (lua_isnil(L, index)) {
      return null;
    } if (lua_isboolean(L, index)) {
      return lua_toboolean(L, index);
    } else if (lua_isinteger(L, index)) {
      return lua_tointeger(L, index);
    } else if (lua_isstring(L, index)) {
      return to_jsstring(lua_tostring(L, index));
    } else if (lua_isnumber(L, index)) {
      return lua_tonumber(L, index);
    } else if (lua_isuserdata(L, index) || lua_islightuserdata(L, index)) {
      return lua_touserdata(L, index);
    } else if (lua_isthread(L, index)) {
      return LuaState.wrap(lua_tothread(L, index));
    } else {
      if (index < 0) index += top + 1; // Resolve index
      return LuaOpaqueValue(
        lua_type(L, index),
        to_jsstring(lua_tostring(L, index)),
        index,
      );
    }
  }

  /// Pops a value from the stack and moves it to [index], replacing the
  /// value in its place.
  void replace(int index) => lua_replace(L, index);

  /// Rotates stack elements between [index] and the top of stack [n] positions.
  ///
  /// Positive values rotate towards the top of the stack and negative values
  /// rotate towards the bottom of the stack, Example:
  ///
  ///     state.pushAll(["a", "b", "c", "d"]);
  ///     state.rotate(-4, 1);
  ///     expect(state.values(4), equals(["d", "a", "b", "c"]));
  ///     state.rotate(-4, -3);
  ///     expect(state.values(4), equals(["c", "d", "a", "b"]));
  void rotate(int index, int n) => lua_rotate(L, index, n);

  /// Same as [LuaState.at].
  dynamic operator[](int index) => at(index);

  /// Sets the value in the stack at [index] to [value].
  operator[]=(int index, dynamic value) {
    if (index < 0) index += top + 1; // Resolve index before push
    push(value);
    replace(index);
  }

  /// Gets [count] number of values in the stack, starting at [start].
  ///
  /// This returns values in the order that they were pushed, Example:
  ///
  ///     state.push("Hello");
  ///     state.push(1234);
  ///     state.push(4321);
  ///     print(state.values(3)); // prints [Hello, 1234, 4321]
  ///
  /// The [start] arg defaults to -[count], meaning it will return the
  /// last [count] values pushed to the stack.
  List<dynamic> values(int count, [int? start]) {
    start ??= -count;
    if (start < 0) start += lua_gettop(L) + 1;
    return List<dynamic>.generate(count, (i) => at(start! + i));
  }

  /// Pops a single value from the stack, returning it.
  dynamic popValue() {
    var o = at(-1);
    pop();
    return o;
  }

  /// Converts the top to a string and pops it, use this instead of
  /// `pop().toString()`.
  String popString() {
    assert(top > 0);
    var str = lua_tostring(L, -1);
    pop();
    return str == null ? "Unknown" : to_jsstring(str);
  }

  /// Same as [LuaState.popString] but for multiple values.
  ///
  /// This returns values in the order they were pushed.
  List<String> popStrings(int n) {
    var o = List<String>.generate(n, (i) {
      var lstring = lua_tostring(L, i - n);
      return lstring == null ? "Unknown" : to_jsstring(lstring);
    });
    pop(n);
    return o;
  }

  /// Pops a number of values from the stack and returns a list of those values.
  ///
  /// This returns values in the order they were pushed.
  List<dynamic> popValues(int count) {
    var o = List.generate(count, (index) => at(index - count));
    pop(count);
    return o;
  }

  /// Pops a number of values from the stack, discarding them.
  void pop([int count = 1]) {
    lua_pop(L, count);
  }

  dynamic _convertCFunction(dynamic fn) {
    if (fn is LuaCFunction) {
      return allowInterop((lua_State L) => fn(LuaState.wrap(L)));
    } else if (fn is LuaFunction) {
      return allowInterop((lua_State L) {
        var state = LuaState.wrap(L);
        var ret = fn(state, state.values(state.top));
        state.pushAll(ret);
        return ret.length;
      });
    } else if (fn is lua_CFunction) {
      return allowInterop(fn);
    } else {
      throw LuaException("Unsupported function type: '${fn.runtimeType}'");
    }
  }

  /// Pushes a value to the stack, automatically converting Dart types to
  /// their equivalent Lua counterparts.
  ///
  /// The following Dart types are supported:
  /// [Null], [bool], [int], [double], [String], [Function], [JsFunction],
  /// [LuaState], [lua_State], [LuaOpaqueValue].
  ///
  /// Dart types that are not supported are converted to light userdata which
  /// can be retrieved again from Dart later.
  void push(dynamic value) {
    if (value == null) {
      lua_pushnil(L);
    } if (value is bool) {
      lua_pushboolean(L, value ? 1 : 0);
    } else if (value is int) {
      lua_pushinteger(L, value);
    } else if (value is double) {
      lua_pushnumber(L, value);
    } else if (value is JsFunction) {
      lua_pushcfunction(L, value);
    } else if (value is Function) {
      lua_pushcfunction(L, _convertCFunction(value));
    } else if (value is String) {
      lua_pushstring(L, to_luastring(value));
    } else if (value is LuaState) {
      if (value == this) {
        pushThread();
      } else {
        // You can only push the current thread on the stack so we have to do
        // that to the target state and then xmove it to the current state.
        value.pushThread();
        value.xmove(this, 1);
      }
    } else if (value is lua_State) {
      if (value == L) {
        pushThread();
      } else {
        // Same as before but without the wrapper
        lua_pushthread(value);
        lua_xmove(value, L, 1);
      }
    } else if (value is LuaOpaqueValue) {
      var out = at(value.index);
      // Verify if the stack still contains the value we want to push
      if (value == out) {
        dup(value.index);
      } else {
        throw LuaException("Attempted to push invalid LuaOpaqueValue");
      }
    } else {
      lua_pushlightuserdata(L, value);
    }
  }

  /// Same as [LuaState.push] but pushes multiple values.
  void pushAll(Iterable<dynamic> values) => values.forEach(push);

  /// Checks if the value at [index] is nil.
  bool isNil([int index = -1]) => lua_isnil(L, index);

  /// Checks if [index] is a valid stack index.
  bool isNone([int index = -1]) => lua_isnone(L, index);

  /// Checks if the value at [index] is nil or if the index is invalid.
  bool isNoneOrNil([int index = -1]) => lua_isnoneornil(L, index);

  /// Checks if the value at [index] is a number.
  bool isNumber([int index = -1]) => lua_isnumber(L, index);

  /// Checks if the value at [index] is a string.
  bool isString([int index = -1]) => lua_isstring(L, index);

  /// Checks if the value at [index] is a table.
  bool isTable([int index = -1]) => lua_istable(L, index);

  /// Checks if the value at [index] is a thread.
  bool isThread([int index = -1]) => lua_isthread(L, index);

  /// Checks if the value at [index] is userdata.
  bool isUserdata([int index = -1]) => lua_isuserdata(L, index);

  /// Checks if the current thread is yieldable.
  bool isYieldable() => lua_isyieldable(L);

  /// Returns the length of the value at [index], equivalent to the # operator.
  ///
  /// This function may invoke the __length metamethod, to avoid this behavior
  /// use [LuaState.rawlen].
  int len(int index) => luaL_len(L, index);

  /// Returns the raw length of the value at [index].
  int rawLen(int index) => lua_rawlen(L, index);

  /// Loads library if not loaded already and pushes it on the stack.
  ///
  /// If [global] is true the library is put in _G as [modname].
  ///
  /// This function is commonly used to load builtin libraries, Example:
  ///
  ///
  void requiref(String modname, dynamic fn, [bool global = true]) =>
    luaL_requiref(
      L, to_luastring(modname), _convertCFunction(fn), global ? 1 : 0
    );

  /// Loads code from a buffer whether it be Lua or compiled bytecode and
  /// pushes the resulting lua function to the stack.
  ///
  /// If code fails to parse or compile, a [LuaException] is thrown.
  void load(List<int> data) {
    var t = top;
    int code;
    if ((code = luaL_loadstring(L, toUint8Array(data))) != 0) {
      // Sometimes Fengari will return an invalid error code and not push an
      // error string but still call our lua_atnativeerror, at the moment these
      // types of errors are not properly propagated using the LuaException but
      // are logged in console.
      var e = "Unknown load error $code";
      if (lua_gettop(L) > t) { // Error string was pushed
        e = popString();
      } // Else error wasn't pushed, Fengari bug.
      throw LuaException(e);
    }
  }

  /// Same as [LuaState.load] but loads from a [String] instead.
  void loadString(String string) => load(Utf8Codec().encode(string));

  /// Similar to [LuaState.load] but returns false on an error instead of
  /// throwing an exception.
  ///
  /// If loading [data] fails the error is pushed to the stack, errors can be
  /// any object so to retrieve it for printing use [LuaState.popString].
  bool tryLoad(List<int> data) => luaL_loadstring(L, toUint8Array(data)) == 0;

  /// Same as [LuaState.tryLoad] but loads from a [String] instead.
  bool tryLoadstring(String string) => tryLoad(Utf8Codec().encode(string));

  /// Pops a value and calls it, may throw a [LuaException].
  ///
  /// If nresults is -1 this function will return a variable number of results.
  List<dynamic> call([
    Iterable<dynamic> args = const [],
    int results = -1,
  ]) {
    var startTop = top;
    pushAll(args);
    if (lua_pcall(L, args.length, results, 0) != 0) {
      throw LuaException(popString());
    }
    return popValues(top - (startTop - 1));
  }

  /// Closes the Lua state
  void close() => lua_close(L);

  // Since this is just a wrapper we guarantee equality between [LuaState]s
  // that wrap the same internal lua state.
  @override
  int get hashCode => L.hashCode;

  @override
  bool operator==(other) =>
    other is LuaState &&
    other.L == L;
}