process.on('unhandledRejection', error => { assert.fail(error); });

const assert = require('assert').strict;

// Load moc.js
const moc = require('moc.js');

// Store files
moc.Motoko.saveFile('empty.mo', '');
moc.Motoko.saveFile('ok.mo', '1');
moc.Motoko.saveFile('bad.mo', '1+');

// Compile the empty module in wasi and dfinity mode
const empty_wasm_plain = moc.Motoko.compileWasm('wasi', 'empty.mo');
const empty_wasm_dfinity = moc.Motoko.compileWasm('dfinity', 'empty.mo');

// For the plain module...
// Check that the code looks like a WebAssembly binary
assert.equal(typeof(empty_wasm_plain), 'object');
assert.deepEqual(empty_wasm_plain.code.subarray(0,4), new Uint8Array([0, 97, 115, 109]));
assert.deepEqual(empty_wasm_plain.code.subarray(4,8), new Uint8Array([1, 0, 0, 0]));
assert.equal(typeof(empty_wasm_plain.diagnostics), 'object');
assert.equal(empty_wasm_plain.diagnostics.length, 0);

// Check that the WebAssembly binary can be loaded
WebAssembly.compile(empty_wasm_plain.code);

// Now again for the dfinity module
assert.equal(typeof(empty_wasm_dfinity), 'object');
assert.deepEqual(empty_wasm_plain.code.subarray(0,4), new Uint8Array([0, 97, 115, 109]));
assert.deepEqual(empty_wasm_plain.code.subarray(4,8), new Uint8Array([1, 0, 0, 0]));
assert.equal(typeof(empty_wasm_dfinity.diagnostics), 'object');
assert.equal(empty_wasm_dfinity.diagnostics.length, 0);

WebAssembly.compile(empty_wasm_dfinity.code);

// The plain and the dfinity module should not be the same
assert.notEqual(empty_wasm_plain.code, empty_wasm_dfinity.code);

// Check if error messages are correctly returned
const bad_result = moc.Motoko.compileWasm('dfinity', 'bad.mo');
// Uncomment to see what to paste below
// console.log(JSON.stringify(bad_result, null, 2));
assert.deepStrictEqual(bad_result, {
  "diagnostics": [
    {
      "range": {
        "start": {
          "line": 0,
          "character": 2
        },
        "end": {
          "line": 0,
          "character": 2
        }
      },
      "severity": 1,
      "source": "bad.mo",
      "message": "unexpected end of input, expected one of token or <phrase> sequence:\n  <exp_bin(ob)>"
    }
  ],
  "code": null,
});

// Check the check command (should print errors, but have no code)
assert.deepStrictEqual(moc.Motoko.check('ok.mo'), {
  "diagnostics": [],
  "code": null
});

assert.deepStrictEqual(moc.Motoko.check('bad.mo'), {
  "diagnostics": [
    {
      "range": {
        "start": {
          "line": 0,
          "character": 2
        },
        "end": {
          "line": 0,
          "character": 2
        }
      },
      "severity": 1,
      "source": "bad.mo",
      "message": "unexpected end of input, expected one of token or <phrase> sequence:\n  <exp_bin(ob)>"
    }
  ],
  "code": null
});
