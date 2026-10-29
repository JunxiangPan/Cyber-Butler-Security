from astrbot.api.event import filter

class Main:
    def __init__(self, context):
        self.context = context

    async def hello(self, event):
        return "hello"
