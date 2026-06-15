import sys, json
sys.path.insert(0, "compressor_sw")
from posit_compress import compress, decompress

with open("compressor_sw/test_input.txt") as f:
    data = json.load(f)
words = data["words"]
print("Loaded", len(words), "words from test_input.txt (32-bit)")

c = compress(words, nbits=32, es=0, block_size=64)
rec = decompress(c)
print("Roundtrip match?", rec == words)
print("orig bytes:", len(words)*4, "comp bytes:", len(c), "ratio:", round(len(c)/(len(words)*4), 3))

# Regenerate the test_output using the current (correct 3-stage) compressor
result = {
  "compression_result": {
    "original_count": len(words),
    "original_bytes": len(words)*4,
    "compressed_bytes": len(c),
    "compression_ratio": len(c) / (len(words)*4),
    "nbits": 32,
    "es": 0,
    "original_words": words,
    "compressed_hex": c.hex()
  }
}
with open("compressor_sw/test_output.txt", "w") as f:
    json.dump(result, f, indent=2)
print("Wrote fresh compressor_sw/test_output.txt (full diffnb->bit->rze, 32b words, 64pkt packets)")

# Quick check via the decompressor too
import subprocess, os
# run the decompressor demo (it will load the fresh test_output and write outputs)
res = subprocess.run([sys.executable, "decompressor_sw/posit_decompress.py"], capture_output=True, text=True)
print("decompressor demo stdout tail:")
print(res.stdout[-500:] if len(res.stdout)>500 else res.stdout)
print("decompressor returncode:", res.returncode)
if res.returncode == 0:
    print("Decompressor demo also succeeded with the new data.")
