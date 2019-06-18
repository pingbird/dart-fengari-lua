import 'dart:html';
import 'package:fengari_lua/lua.dart';

void main() {
  TextAreaElement code = querySelector("#lua-code");
  var output = querySelector("#output");
  var outputHeader = querySelector("#output-header");
  var clearBtn = querySelector("#clear-btn");

  LuaState state;

  void initState() {
    if (state != null) state.close();
    state = LuaState();
    state.push((LuaState state, List args) {
      output.text += args.join("\t") + "\n";
      return [];
    });
    state.setGlobal("print");
  }

  initState();

  void outputClear() {
    output.text = "";
    output.style.visibility = "hidden";
    outputHeader.style.visibility = "hidden";
    clearBtn.classes.add("mdl-button--disabled");
  }

  void outputEnable() {
    output.style.visibility = "visible";
    outputHeader.style.visibility = "visible";
    clearBtn.classes.remove("mdl-button--disabled");
  }

  querySelector("#clear-btn").onClick.listen((_) {
    outputClear();
  });

  querySelector("#reset-btn").onClick.listen((_) {
    initState();
  });

  querySelector("#run-btn").onClick.listen((_) {
    output.text = "";
    outputEnable();
    try {
      state.loadString(code.value);
      state.call([], 0);
    } catch (e) {
      output.text += e.toString();
    }
  });
}
