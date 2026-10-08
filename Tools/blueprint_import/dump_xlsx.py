import sys, zipfile, re, json
import xml.etree.ElementTree as ET
NS={'m':'http://schemas.openxmlformats.org/spreadsheetml/2006/main',
    'r':'http://schemas.openxmlformats.org/officeDocument/2006/relationships'}
z=zipfile.ZipFile(sys.argv[1])
ss=[]
root=ET.fromstring(z.read('xl/sharedStrings.xml'))
for si in root.findall('m:si',NS):
    ss.append(''.join(t.text or '' for t in si.iter('{%s}t'%NS['m'])))
wb=ET.fromstring(z.read('xl/workbook.xml'))
rels=ET.fromstring(z.read('xl/_rels/workbook.xml.rels'))
rmap={r.get('Id'):r.get('Target') for r in rels}
out={}
for sh in wb.find('m:sheets',NS):
    name=sh.get('name'); rid=sh.get('{%s}id'%NS['r'])
    path='xl/'+rmap[rid].lstrip('/').replace('xl/','')
    x=ET.fromstring(z.read(path))
    rows=[]
    for row in x.iter('{%s}row'%NS['m']):
        cells=[]
        for c in row.findall('m:c',NS):
            t=c.get('t'); v=c.find('m:v',NS); val=None
            if t=='s' and v is not None: val=ss[int(v.text)]
            elif t=='inlineStr':
                val=''.join(tt.text or '' for tt in c.iter('{%s}t'%NS['m']))
            elif v is not None: val=v.text
            if val not in (None,''): cells.append((c.get('r'),val))
        if cells: rows.append(cells)
    out[name]=rows
json.dump(out,open(sys.argv[2],'w'),ensure_ascii=False,indent=0)
for k,v in out.items(): print(k, len(v))
