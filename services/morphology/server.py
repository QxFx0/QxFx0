import json
import sys
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse

try:
    import pymorphy3
except ImportError:
    print("pymorphy3 not available", file=sys.stderr)
    pymorphy3 = None


POS_MAP = {
    "NOUN": "NOUN", "ADJF": "ADJ", "ADJS": "ADJ",
    "VERB": "VERB", "INFN": "VERB", "PRTF": "ADJ", "PRTS": "ADJ",
    "GRND": "ADV",
    "ADVB": "ADV",
    "NPRO": "PRON",
    "PREP": "PREP",
    "CONJ": "CONJ",
    "PRCL": "PART",
    "INTJ": "INTJ",
    "NUMR": "NUM",
    "COMP": "ADV",
    None: "UNKN",
}

CASE_MAP = {
    "nomn": "NOMN", "gent": "GENT", "datv": "DATV",
    "accs": "ACCS", "ablt": "ABLT", "loct": "LOCT",
    "gen1": "GENT", "gen2": "GENT", "acc2": "ACCS",
    "loc1": "LOCT", "loc2": "LOCT",
}

NUMBER_MAP = {"sing": "SING", "plur": "PLUR"}
GENDER_MAP = {"masc": "MASC", "femn": "FEMN", "neut": "NEUT"}
PERSON_MAP = {"1per": "1PER", "2per": "2PER", "3per": "3PER"}
TENSE_MAP = {"pres": "PRES", "past": "PAST", "futr": "FUTR"}


def analyze_word(word):
    if not word.strip():
        return {"word": word, "lemma": word, "pos": None, "case": None, "number": None, "gender": None, "tense": None, "mood": None, "person": None}
    if pymorphy3 is None:
        return {"word": word, "lemma": word, "pos": "UNKN", "case": None, "number": None, "gender": None, "tense": None, "mood": None, "person": None}
    try:
        morph = pymorphy3.MorphAnalyzer()
        p = morph.parse(word)[0]
        tag = p.tag
        return {
            "word": word,
            "lemma": p.normal_form,
            "pos": POS_MAP.get(tag.POS, "UNKN"),
            "case": CASE_MAP.get(tag.case),
            "number": NUMBER_MAP.get(tag.number),
            "gender": GENDER_MAP.get(tag.gender),
            "tense": TENSE_MAP.get(tag.tense),
            "mood": tag.mood.upper() if tag.mood else None,
            "person": PERSON_MAP.get(tag.person),
        }
    except Exception as e:
        return {"word": word, "lemma": word, "pos": "UNKN", "case": None, "number": None, "gender": None, "tense": None, "mood": None, "person": None, "error": str(e)}


class MorphologyHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        parsed = urlparse(self.path)
        if parsed.path == "/morph":
            self._handle_morph()
        elif parsed.path == "/health":
            self._handle_health()
        else:
            self.send_response(404)
            self.end_headers()

    def _handle_morph(self):
        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length) if content_length else b""
        try:
            data = json.loads(body)
            text = data.get("text", "")
            tokens = text.split(" ") if text else []
            result = [analyze_word(w) for w in tokens]
            self._json_response(200, {"tokens": result})
        except Exception as e:
            self._json_response(400, {"error": str(e)})

    def _handle_health(self):
        status = {"healthy": pymorphy3 is not None}
        code = 200 if pymorphy3 is not None else 503
        self._json_response(code, status)

    def _json_response(self, code, data):
        body = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        if "--quiet" not in sys.argv:
            super().log_message(fmt, *args)


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 and sys.argv[1].isdigit() else 8081
    server = HTTPServer(("127.0.0.1", port), MorphologyHandler)
    print(f"morphology service listening on 127.0.0.1:{port}", file=sys.stderr)
    server.serve_forever()


if __name__ == "__main__":
    main()
