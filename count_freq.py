import sys, os, codecs

if __name__ == '__main__':
    if len(sys.argv) != 2:
        print >> sys.stderr, 'Usage: python %s <input>'%sys.argv[0]
        sys.exit()
    freqs = {}
    with codecs.open(sys.argv[1], 'r', 'utf8') as fin:
        for idx,line in enumerate(fin):
            if idx%100000 == 0:
                print (idx)
            words = line.strip().split()
            for word in words:
                if word not in freqs:
                    freqs[word] = 0
                freqs[word] = freqs[word]+1
        sums = [1,2,3,4]
        res = {}
        for k in freqs:
            for sum in sums:
                if freqs[k] >= sum:
                    if sum not in res:
                        res[sum] = 0
                    res[sum] += 1
        print (res)
