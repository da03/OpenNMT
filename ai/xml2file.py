import sys, codecs, os
from xml.dom.minidom import parse
import xml.dom.minidom


if __name__ == '__main__':
    if len(sys.argv) != 3:
        print >> sys.stderr, 'Usage: python %s <input> <output>'%sys.argv[0]
        sys.exit(1)

filename = sys.argv[1]
tmp = '.tmp'
with codecs.open(tmp, 'w', 'utf8') as fout:
    fout.write(codecs.open(filename,'r','utf8').read().replace(u'&', u'&amp;'))

dom = xml.dom.minidom.parse(tmp)
os.remove(tmp)
seg = dom.getElementsByTagName("seg")

with codecs.open(sys.argv[2], mode='w', encoding='utf8') as fout:
    for i, item in enumerate(seg):
        id = int(item.attributes.items()[0][1])
        assert id == (i+1), (i, item)
        sent = item.firstChild.data.replace(u'&amp;', u'&')
        fout.write(sent+'\n')
