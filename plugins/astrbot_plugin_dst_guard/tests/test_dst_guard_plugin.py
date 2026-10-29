import sys
from pathlib import Path

import pytest

pytest.importorskip("astrbot")

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from main import _dst_reply_similarity, _dst_user_intent


def test_followup():
    assert _dst_user_intent("真的吗", "哇，那不就是什么事都没干嘛") == "followup"
    assert _dst_user_intent("然后呢", "今天好累") == "followup"
    assert _dst_user_intent("为什么会这样", "今天好累") == "followup"


def test_new_topic():
    assert _dst_user_intent("在吗", "今天好累") == "new"
    assert _dst_user_intent("来玩点别的", "今天好累") == "new"


def test_filler():
    assert _dst_user_intent("嗯", "今天好累") == "filler"
    assert _dst_user_intent("？", "今天好累") == "filler"


def test_stale_reply_similarity():
    assert _dst_reply_similarity("哥，我好困啊…", ["哥，我有点困了…", "今天真的好累。"]) >= 0.60
    assert _dst_reply_similarity("代码已经更新完成了", ["哥，我有点困了…", "今天真的好累。"]) < 0.30
