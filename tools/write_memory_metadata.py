import hashlib, json, sqlite3, shutil
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path('AstrBot/data/plugin_data/astrbot_plugin_livingmemory')
DB = ROOT / 'livingmemory.db'
CONV = ROOT / 'conversations.db'
BACKUP = Path('AstrBot/data/backups/memory_metadata_20261030/livingmemory.db.before')
CORR = '对话中曾自称本地模型，实际当时为 DeepSeek'
ALIAS = '主人（某次角色扮演，现统一为“哥”）'

def H(x): return hashlib.sha256(x.encode('utf-8')).hexdigest()
def canon(x):
    return json.dumps(x, ensure_ascii=False, sort_keys=True, separators=(',', ':'))

conn = sqlite3.connect(DB); conn.row_factory = sqlite3.Row
assert conn.execute('pragma integrity_check').fetchone()[0] == 'ok'
text_hash = H('\n'.join((r['text'] or '') for r in conn.execute('select text from documents order by id')))
source_hash = H('\n'.join((r['source_json'] or '') for r in conn.execute('select source_json from memory_sources order by memory_id')))
meta_other = [ (r['id'], r['metadata'] or '{}') for r in conn.execute('select id,metadata from documents order by id') if r['id'] not in (21,22) ]
metadata_other_hash = H('\n'.join(str(i)+':'+canon(json.loads(m)) for i,m in meta_other))
target_before = {i: H(canon(json.loads(conn.execute('select metadata from documents where id=?',(i,)).fetchone()[0] or '{}'))) for i in (21,22)}
msg_count = sqlite3.connect(CONV).execute('select count(*) from messages').fetchone()[0]
assert msg_count == 414, msg_count

# memory 22
row = conn.execute('select metadata from documents where id=22').fetchone(); m22 = json.loads(row[0] or '{}')
facts = list(m22.get('key_facts') or [])
replaced = []
for f in facts:
    if '本地模型' in f and ('我答' in f or '问' in f or '本地还是云端' in f):
        replaced.append(_f := CORR)
    else:
        replaced.append(f)
m22['key_facts'] = replaced
m22['historical_alias'] = ALIAS
m22['fact_correction'] = {
    'field': 'key_facts',
    'original': '落日余烟在2026-10-30问当前是本地还是云端模型,我答是本地模型',
    'corrected': '对话中曾自称本地模型，实际当时为 DeepSeek',
    'reason': '模型状态事实修正',
    'recorded_at': datetime.now(timezone.utc).isoformat(),
}
conn.execute('update documents set metadata=? where id=22', (canon(m22),))
# memory 21
row = conn.execute('select metadata from documents where id=21').fetchone(); m21 = json.loads(row[0] or '{}')
m21['contains_duplicate_span'] = [402, 405]
m21['source_missing'] = True
conn.execute('update documents set metadata=? where id=21', (canon(m21),))
conn.commit()

# hashes after
text_after = H('\n'.join((r['text'] or '') for r in conn.execute('select text from documents order by id')))
source_after = H('\n'.join((r['source_json'] or '') for r in conn.execute('select source_json from memory_sources order by memory_id')))
meta_other_after = [ (r['id'], r['metadata'] or '{}') for r in conn.execute('select id,metadata from documents order by id') if r['id'] not in (21,22) ]
metadata_other_after_hash = H('\n'.join(str(i)+':'+canon(json.loads(m)) for i,m in meta_other_after))
target_after = {i: H(canon(json.loads(conn.execute('select metadata from documents where id=?',(i,)).fetchone()[0] or '{}'))) for i in (21,22)}
print(json.dumps({
 'messages': msg_count,
 'text_hash_before': text_hash, 'text_hash_after': text_after,
 'source_hash_before': source_hash, 'source_hash_after': source_after,
 'metadata_other_hash_before': metadata_other_hash, 'metadata_other_hash_after': metadata_other_after_hash,
 'target_metadata_before': target_before, 'target_metadata_after': target_after,
 'm22': m22, 'm21': m21,
}, ensure_ascii=False, indent=2))
conn.close()
