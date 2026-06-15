import sys
sys.path.insert(0, "compressor_sw")
from posit_compress import compress, decompress, _make_synthetic

for nbits, es, length, kind in [(32,0,64,"sine"), (32,3,64,"sine"), (16,0,200,"sparse"), (64,0,30,"sine")]:
    words = _make_synthetic(length, nbits, kind)
    c = compress(words, nbits=nbits, es=es, block_size=64)
    rec = decompress(c)
    ok = (rec == words)
    print(f"nbits={nbits} es={es} len={length} {kind}: match={ok}  orig_len={len(words)} rec_len={len(rec)}")
    if not ok:
        minl = min(len(rec), len(words))
        for i in range(minl):
            if rec[i] != words[i]:
                print(f"  first diff @{i}: got {hex(rec[i])} expected {hex(words[i])}")
                break
        if len(rec) != len(words):
            print(f"  length mismatch {len(rec)} vs {len(words)}")
print("done")
