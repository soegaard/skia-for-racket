"""Reference source and HTML checks. Runtime binding identity is checked separately in Racket.

The source reader deliberately supports the native definition forms used by this manual.
It rejects unsupported signatures rather than treating a guessed arity as evidence.
"""
from __future__ import annotations

from collections import Counter
import base64
import hashlib
from html import escape, unescape
from html.parser import HTMLParser
import json
import os
from pathlib import Path, PurePosixPath
import re
from urllib.parse import parse_qs, unquote, urlsplit

REFERENCE = Path('scribblings/reference')
MANIFEST = Path('api/reference-coverage.json')
DEFINITION_FORMS = {'defproc', 'defform', 'defparam', 'defstruct*', 'defthing'}
OTHER_DEFINITIONS = {'defproc*', 'defform*', 'defstruct', 'deftogether'}


class CheckError(ValueError):
    pass


def need(condition, message):
    if not condition:
        raise CheckError(message)


def safe_file(root: Path, relative: str) -> Path:
    name = PurePosixPath(relative)
    need(relative and not name.is_absolute() and '\\' not in relative
         and ':' not in relative and all(p not in ('', '.', '..') for p in relative.split('/')),
         f'unsafe source path: {relative!r}')
    path = root / relative
    need(path.resolve().is_relative_to(root.resolve()), f'path escapes root: {relative}')
    need(not path.is_symlink(), f'symlink in source inventory: {relative}')
    return path


class String(str):
    """Distinguish a literal string from an identifier in a documentation header."""


class Reader:
    """Small, strict S-expression reader for definition headers, not a Racket evaluator."""
    def __init__(self, text: str, position: int = 0):
        self.text, self.position = text, position

    def skip(self):
        while self.position < len(self.text):
            if self.text[self.position].isspace():
                self.position += 1
            elif self.text.startswith(';', self.position):
                end = self.text.find('\n', self.position)
                self.position = len(self.text) if end < 0 else end + 1
            elif self.text.startswith('#|', self.position):
                depth = 1
                self.position += 2
                while depth and self.position < len(self.text):
                    if self.text.startswith('#|', self.position):
                        depth += 1
                        self.position += 2
                    elif self.text.startswith('|#', self.position):
                        depth -= 1
                        self.position += 2
                    else:
                        self.position += 1
                need(depth == 0, 'unterminated block comment')
            elif self.text.startswith('#;', self.position):
                self.position += 2
                self.read()
            else:
                break

    def read(self):
        self.skip()
        need(self.position < len(self.text), 'unexpected end of header')
        ch = self.text[self.position]
        self.position += 1
        if ch in '([{':
            closing = dict(zip('([{', ')]}'))[ch]
            result = []
            while True:
                self.skip()
                need(self.position < len(self.text), 'unclosed header')
                if self.text[self.position] == closing:
                    self.position += 1
                    return result
                need(self.text[self.position] not in ')]}', 'mismatched header delimiter')
                result.append(self.read())
        if ch == '"':
            result = ''
            while self.position < len(self.text):
                ch = self.text[self.position]
                self.position += 1
                if ch == '"':
                    return String(result)
                if ch == '\\':
                    need(self.position < len(self.text), 'unterminated string escape')
                    ch = self.text[self.position]
                    self.position += 1
                    result += {'n': '\n', 'r': '\r', 't': '\t'}.get(ch, ch)
                else:
                    result += ch
            raise CheckError('unterminated string')
        if ch in "'`,":
            prefix = {"'": 'quote', '`': 'quasiquote', ',': 'unquote'}[ch]
            if ch == ',' and self.text[self.position:self.position + 1] == '@':
                self.position += 1
                prefix = 'unquote-splicing'
            return [prefix, self.read()]
        need(ch not in ')]}', 'unexpected closing delimiter')
        start = self.position - 1
        while self.position < len(self.text):
            if self.text[self.position].isspace() or self.text[self.position] in '()[]{};':
                break
            self.position += 1
        return self.text[start:self.position]


def brace_end(text, position):
    """Skip a Scribble body without counting braces inside embedded code strings."""
    depth, pos = 1, position + 1
    while depth and pos < len(text):
        if text[pos] == '@':
            match = re.match(r'@[A-Za-z][A-Za-z0-9?!*/+<>:=_-]*', text[pos:])
            code = pos + len(match[0]) if match else pos + 1
            if text[code:code + 1] in ('[', '(', '"'):
                reader = Reader(text, code)
                reader.read()
                pos = reader.position
                continue
        depth += (text[pos] == '{') - (text[pos] == '}')
        pos += 1
    need(depth == 0, 'unclosed Scribble text body')
    return pos


def commands(text, *, recursive=False):
    """Read top-level @ commands; do not mistake example code for a definition."""
    pos = 0
    while pos < len(text):
        at = text.find('@', pos)
        if at < 0:
            return
        pos = at + 1
        if text.startswith(';', pos):
            pos += 1
            if pos < len(text) and text[pos] in '([{':
                if text[pos] == '{':
                    pos = brace_end(text, pos)
                else:
                    reader = Reader(text, pos)
                    reader.read()
                    pos = reader.position
            else:
                end = text.find('\n', pos)
                pos = len(text) if end < 0 else end + 1
            continue
        if pos < len(text) and text[pos] in '("':
            reader = Reader(text, pos)
            reader.read()
            pos = reader.position
            continue
        match = re.match(r'[A-Za-z][A-Za-z0-9?!*/+<>:=_-]*', text[pos:])
        if not match:
            continue
        name = match.group()
        pos += len(name)
        header = None
        if text[pos:pos + 1] == '[':
            reader = Reader(text, pos)
            header = reader.read()
            pos = reader.position
        body_start = pos if text[pos:pos + 1] == '{' else None
        if body_start is not None:
            pos = brace_end(text, pos)
        yield name, header, at
        if recursive and body_start is not None:
            for nested, arguments, offset in commands(text[body_start + 1:pos - 1], recursive=True):
                yield nested, arguments, body_start + 1 + offset


def procedure_shape(header):
    need(isinstance(header, list) and len(header) >= 2, 'procedure needs a result contract')
    call = header[0]
    need(isinstance(call, list) and call and type(call[0]) is str, 'invalid procedure header')
    required, optional, keywords, required_keywords = 0, 0, [], []
    arguments, rest = [], False
    for field in call[1:]:
        if type(field) is str and field in ('...', '...+'):
            need(not rest and not optional and arguments
                 and arguments[-1]['keyword'] is None and not arguments[-1]['optional'],
                 'unsupported rest/case signature')
            rest = True
            if field == '...':
                required -= 1
            arguments[-1]['repeat'] = 'zero-or-more' if field == '...' else 'one-or-more'
            continue
        need(isinstance(field, list), 'unsupported rest/case signature')
        keyword = bool(field and isinstance(field[0], str) and field[0].startswith('#:'))
        need(not rest or keyword, 'unsupported rest/case signature after ellipsis')
        need(len(field) in ((3, 4) if keyword else (2, 3)), 'invalid argument specification')
        has_default = len(field) == (4 if keyword else 3)
        if keyword:
            key = field[0][2:]
            need(key not in keywords, 'duplicate keyword in procedure header')
            keywords.append(key)
            if not has_default:
                required_keywords.append(key)
        elif has_default:
            optional += 1
        else:
            need(optional == 0, 'required positional argument follows an optional one')
            required += 1
        arguments.append(dict(name=str(field[1 if keyword else 0]),
                              keyword=field[0][2:] if keyword else None,
                              optional=has_default))
    mask = -(1 << required) if rest else sum(1 << n for n in range(required, required + optional + 1))
    return dict(name=call[0], kind='procedure', arity_mask=str(mask),
                allowed_keywords=sorted(keywords), required_keywords=sorted(required_keywords),
                arguments=arguments)


def constant_shape(header):
    """Read literal predicates and the reviewed immutable-symbol-vector contract.

    Contract expressions are not evaluated here. Keep other compound contracts
    unsupported until the native reader and live value check also support them.
    """
    need(isinstance(header, list) and len(header) == 2
         and type(header[0]) is str and not header[0].startswith('#:'),
         'unsupported constant declaration; expected name and contract')
    contract = header[1]
    shape = dict(name=header[0], kind='value', arguments=[], value_kind='constant')
    if type(contract) is str and not contract.startswith('#:'):
        return dict(shape, value_predicate=contract)
    need(contract == ['and/c', ['vectorof', 'symbol?'], 'immutable?']
         and all(type(atom) is str for atom in [contract[0], *contract[1], contract[2]]),
         'unsupported compound constant contract')
    return dict(shape, value_contract=contract)


def structure_shapes(header):
    """The immutable transparent, no-supertype defstruct* subset used for RGBA.

    Derive member coverage from the real declaration. Unsupported field/constructor
    options fail closed until both this reader and the Racket reader support them.
    """
    need(isinstance(header, list) and len(header) == 3 and header[2] == '#:transparent',
         'unsupported structure options; expected an immutable transparent defstruct*')
    name, fields = header[:2]
    need(type(name) is str and not name.startswith('#:'), 'unsupported structure name/supertype')
    need(isinstance(fields, list), 'invalid structure fields')
    need(all(isinstance(field, list) and len(field) == 2 and type(field[0]) is str
             and not field[0].startswith('#:') for field in fields), 'unsupported structure field')
    names = [field[0] for field in fields]
    need(len(set(names)) == len(names), 'duplicate structure field')
    constructor = procedure_shape([[name, *fields], name + '?'])
    result = [dict(constructor, definition_group=name, structure_role='constructor'),
              dict(name='struct:' + name, kind='value', arguments=[], definition_group=name,
                   structure_role='descriptor', value_kind='struct-type'),
              dict(procedure_shape([[name + '?', ['v', 'any/c']], 'boolean?']),
                   definition_group=name, structure_role='predicate')]
    result += [dict(procedure_shape([[name + '-' + field, ['value', name + '?']], contract]),
                    definition_group=name, structure_role='accessor') for field, contract in fields]
    return result


def document_definitions(root: Path):
    result, visited = [], set()

    def visit(relative):
        need(relative not in visited, f'repeated/cyclic chapter include: {relative}')
        visited.add(relative)
        path = safe_file(root, relative)
        source = path.read_text(encoding='utf-8')
        for form, header, position in commands(source):
            if form == 'include-section':
                need(header and isinstance(header[0], String), 'chapter path must be literal')
                visit((Path(relative).parent / header[0]).as_posix())
            elif form in OTHER_DEFINITIONS:
                raise CheckError(f'extend the checker before using @{form}: {relative}')
            elif form in DEFINITION_FORMS:
                need(header and '#:link-target?' not in header,
                     'definition targets must not be disabled')
                if form == 'defstruct*':
                    for entry in structure_shapes(header):
                        entry.update(chapter=relative, form=form,
                                     line=source.count('\n', 0, position) + 1)
                        result.append(entry)
                    continue
                if form == 'defproc':
                    entry = procedure_shape(header)
                elif form == 'defthing':
                    entry = constant_shape(header)
                elif form == 'defparam':
                    need(len(header) >= 3 and isinstance(header[0], str), 'invalid parameter')
                    entry = dict(name=header[0], kind='parameter', arity_mask='3',
                                 allowed_keywords=[], required_keywords=[], arguments=[])
                else:
                    need(isinstance(header[0], list) and header[0], 'invalid syntax header')
                    entry = dict(name=header[0][0], kind='syntax', arguments=[])
                entry.update(chapter=relative, form=form,
                             line=source.count('\n', 0, position) + 1)
                result.append(entry)
    visit((REFERENCE / 'reference.scrbl').as_posix())
    return result, visited


def export_key(module, name, phase='0', space=None):
    return module, str(phase), space, name


def public_module(path):
    need(path.endswith('.rkt') and not path.startswith('private/'), 'nonpublic module in inventory')
    return 'skia' if path == 'main.rkt' else 'skia/' + path[:-4]


def git_blob(data: bytes):
    return hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()


def source_addition_exports(root, manifest):
    """Verify named additions from pinned source, without claiming runtime reflection."""
    additions = {}
    for item in manifest.get('source_verified_additions', []):
        need(item.get('evidence') == 'source-signature', 'unknown addition evidence kind')
        need(re.fullmatch(r'[0-9a-f]{40}', item['source_commit']), 'invalid source commit')
        path = safe_file(root, item['source_copy'])
        raw = base64.b64decode(b''.join(path.read_bytes().splitlines()), validate=True)
        need(git_blob(raw) == item['source_git_blob'], 'source addition copy changed')
        module = public_module(item['source_path'])
        need(module == item['module'], 'source addition module/path mismatch')
        installed = safe_file(root, item['source_path'])
        if installed.is_file():
            need(installed.read_bytes() == raw, 'source addition differs from checkout')
        text = raw.decode('utf-8')
        need(text.startswith('#lang racket/base\n'), 'unsupported source addition language')
        reader = Reader(text, text.index('\n') + 1)
        forms = []
        while True:
            reader.skip()
            if reader.position == len(text):
                break
            forms.append(reader.read())
        name = item['name']
        need(any(isinstance(f, list) and f and f[0] == 'provide' and name in f[1:]
                 for f in forms), 'addition is not a direct public export')
        found = [f[1] for f in forms if isinstance(f, list) and len(f) >= 3
                 and f[0] == 'define' and isinstance(f[1], list) and f[1]
                 and f[1][0] == name]
        need(len(found) == 1, 'addition needs one direct procedure definition')
        tokens, arguments = list(found[0][1:]), []
        while tokens:
            token = tokens.pop(0)
            keyword = token if type(token) is str and token.startswith('#:') else None
            if keyword:
                need(tokens, 'source keyword has no argument')
                token = tokens.pop(0)
            need(type(token) is str or (isinstance(token, list) and len(token) == 2),
                 'unsupported source procedure argument')
            identifier = token[0] if isinstance(token, list) else token
            need(type(identifier) is str and identifier != '.', 'unsupported source argument')
            arg = ([keyword] if keyword else []) + [identifier, 'any/c']
            if isinstance(token, list):
                arg.append(token[1])
            arguments.append(arg)
        shape = procedure_shape([[name, *arguments], 'any/c'])
        key = export_key(module, name)
        need(key not in additions, 'duplicate source addition')
        additions[key] = dict(shape, phase='0', export_kind='value',
                              evidence='source-signature', source_commit=item['source_commit'])
    return additions


def load_exports(root, manifest):
    exports = {}
    for snapshot in manifest['snapshots']:
        path = safe_file(root, snapshot['file'])
        data = path.read_bytes()
        need(git_blob(data) == snapshot['git_blob'],
             f'snapshot changed; review the coverage mapping: {snapshot["file"]}')
        document = json.loads(data)
        for module in document['modules']:
            name = public_module(module['path'])
            for row in module['exports']:
                key = export_key(name, row['name'], row['phase'], row.get('space'))
                need(key not in exports, f'duplicate snapshot export: {key}')
                exports[key] = row
    for key, row in source_addition_exports(root, manifest).items():
        need(key not in exports, f'addition already appears in a pinned inventory: {key}')
        exports[key] = row
    return exports


def check_source(root: Path, *, documents_only=False, require_complete=False):
    manifest = json.loads(safe_file(root, str(MANIFEST)).read_text(encoding='utf-8'))
    need(manifest.get('schema_version') == 1, 'unknown coverage manifest schema')
    definitions, chapters = document_definitions(root)
    names = Counter(row['name'] for row in definitions)
    need(all(n == 1 for n in names.values()), 'duplicate canonical definition')
    # The present subset uses unique names. Later homonyms need qualified definition IDs,
    # not silent merging.
    by_name = {row['name']: row for row in definitions}
    mapped = manifest['definitions']
    need(len({row['name'] for row in mapped}) == len(mapped), 'duplicate manifest definition')
    need(set(by_name) == {row['name'] for row in mapped}, 'definition/manifest coverage mismatch')
    exports = None if documents_only else load_exports(root, manifest)
    claimed, specs = set(), []
    for row in mapped:
        spec = by_name[row['name']]
        need(spec['chapter'] == row['chapter'], f'wrong canonical chapter: {row["name"]}')
        need(row['exports'] and row['canonical_module'] in row['exports'], 'missing canonical export')
        need(row['phase'] == '0' and row['space'] is None,
             'Reference supports phase 0/default space only')
        for module in row['exports']:
            need(module == 'skia' or (module.startswith('skia/') and '/private/' not in module),
                 'private/non-Skia import path advertised')
            key = export_key(module, row['name'], row['phase'], row['space'])
            need(key not in claimed, f'export claimed twice: {key}')
            claimed.add(key)
            if exports is not None:
                need(key in exports, f'unknown public export: {key}')
                actual = exports[key]
                need(actual['kind'] == spec['kind'], f'kind mismatch: {key}')
                if spec['kind'] in ('procedure', 'parameter'):
                    for field in ('arity_mask', 'allowed_keywords', 'required_keywords'):
                        need(actual[field] == spec[field], f'{field} mismatch: {key}')
        specs.append(dict(spec, exports=row['exports'], canonical_module=row['canonical_module']))
    deferred = []
    if exports is not None:
        policy = manifest['deferred_policy']
        need(policy['stage'] and policy['reason'], 'deferred exports need a stage and reason')
        for module, phase, space, name in sorted(set(exports) - claimed, key=repr):
            deferred.append(dict(module=module, phase=phase, space=space, name=name,
                                 status='deferred', **policy))
        need(not require_complete or not deferred, f'{len(deferred)} exports remain deferred')
    else:
        need(not require_complete, 'documents-only cannot establish complete coverage')
    tutorial_links = manifest.get('tutorial_links', [])
    tutorial_keys = set()
    for link in tutorial_links:
        manual, directory, tag = link['manual'], link['directory'], link['tag']
        safe_file(root, manual)
        need(manual.startswith('scribblings/') and manual.endswith('.scrbl'),
             'invalid tutorial document path')
        need(re.fullmatch(r'skia-tutorials|skia-tutorial-[a-z-]+', directory),
             'invalid tutorial output directory')
        need(isinstance(tag, str) and tag and link['label'].strip(), 'invalid tutorial link')
        key = ('skia/' + manual, tag)
        need(key not in tutorial_keys, 'duplicate tutorial link declaration')
        tutorial_keys.add(key)
    found_links = set()
    for chapter in chapters:
        for form, header, _ in commands((root / chapter).read_text(encoding='utf-8'), recursive=True):
            if form != 'seclink' or not header or '#:doc' not in header:
                continue
            doc = header[header.index('#:doc') + 1]
            if (isinstance(doc, list) and len(doc) == 2 and doc[0] == 'quote'
                and isinstance(doc[1], list) and len(doc[1]) == 2 and doc[1][0] == 'lib'
                and str(doc[1][1]).startswith('skia/scribblings/tutorials/')):
                found_links.add((str(doc[1][1]), str(header[0])))
    need(found_links == tutorial_keys, 'tutorial link/source coverage mismatch')
    section_links = manifest.get('section_links', [])
    section_keys = set()
    for link in section_links:
        chapter, tag = link['chapter'], link['tag']
        need(chapter in chapters, 'section link points outside the Reference')
        need(isinstance(tag, str) and tag and link['label'].strip(), 'invalid section link')
        need(re.fullmatch(r'skia-[a-z-]+[.]html', link['filename']),
             'invalid section filename')
        key = (chapter, tag)
        need(key not in section_keys, 'duplicate section link declaration')
        section_keys.add(key)
        titles = [header for form, header, _ in
                  commands(safe_file(root, chapter).read_text(encoding='utf-8'))
                  if form == 'title']
        need(len(titles) == 1 and '#:tag' in titles[0], 'section needs explicit title tags')
        tags = titles[0][titles[0].index('#:tag') + 1]
        if isinstance(tags, list) and len(tags) == 2 and tags[0] == 'quote':
            tags = tags[1]
        tags = [tags] if isinstance(tags, String) else tags
        need(isinstance(tags, list) and tags and all(isinstance(t, String) for t in tags),
             'unsupported section title tags')
        need(tag in tags, 'section link tag is not declared by its chapter')
        need(str(tags[0]) + '.html' == link['filename'],
             'first chapter tag must preserve the published filename')
    aliases = set()
    for chapter in chapters:
        for form, header, _ in commands(safe_file(root, chapter).read_text(encoding='utf-8')):
            if form != 'title' or not header or '#:tag' not in header:
                continue
            tags = header[header.index('#:tag') + 1]
            if isinstance(tags, list) and len(tags) == 2 and tags[0] == 'quote':
                need(isinstance(tags[1], list) and all(isinstance(t, String) for t in tags[1]),
                     'unsupported chapter aliases')
                if len(tags[1]) > 1:
                    aliases.update((chapter, str(tag)) for tag in tags[1])
    need(aliases <= section_keys, 'chapter aliases are missing from the section-link manifest')
    info = (root / 'info.rkt').read_text(encoding='utf-8')
    need('"scribblings/reference/reference.scrbl" (multi-page)' in info, 'manual not registered')
    return dict(status='passed', documents_only=documents_only, definitions=specs,
                tutorial_links=tutorial_links, section_links=section_links, chapters=sorted(chapters),
                documented_exports=len(claimed), deferred=deferred,
                inventory_checked=exports is not None,
                inventory_exports=len(exports) if exports is not None else None,
                binding_identity_checked=False,
                source_verified_export_additions=(
                    len(manifest.get('source_verified_additions', []))
                    if exports is not None else None),
                reflected_inventory_exports=(
                    len(exports) - len(manifest.get('source_verified_additions', []))
                    if exports is not None else None))


class Page(HTMLParser):
    def __init__(self, text):
        super().__init__(convert_charrefs=True)
        self.anchors, self.links, self.badlinks = Counter(), [], 0
        self.unresolved_references, self.unlinked_identifiers = 0, 0
        self.current = None
        self.feed(text)
        self.close()

    def handle_starttag(self, tag, attributes):
        attrs = dict(attributes)
        for target in set(filter(None, [attrs.get('id'), attrs.get('name') if tag == 'a' else None])):
            self.anchors[target] += 1
        classes = set(attrs.get('class', '').split())
        self.unresolved_references += 'badlink' in classes
        self.unlinked_identifiers += 'RktErr' in classes
        if classes & {'badlink', 'RktErr'}:
            self.badlinks += 1
        if tag == 'a' and 'href' in attrs:
            self.current = [attrs['href'], []]

    def handle_data(self, text):
        if self.current is not None:
            self.current[1].append(text)

    def handle_endtag(self, tag):
        if tag == 'a' and self.current is not None:
            self.links.append((self.current[0], ''.join(self.current[1])))
            self.current = None


def internal_redirect(url):
    """Recognize only the Racket redirect service and this package's manuals."""
    parts = urlsplit(unescape(url))
    if parts.hostname not in {'docs.racket-lang.org', 'download.racket-lang.org'}:
        return None
    if not parts.path.endswith('/local-redirect/index.html'):
        return None
    query = parse_qs(parts.query)
    doc, rel = query.get('doc', []), query.get('rel', [])
    if len(doc) != 1 or len(rel) != 1:
        return None
    if not re.fullmatch(r'skia-reference|skia-tutorials|skia-tutorial-[a-z-]+', doc[0]):
        return None
    target = urlsplit(rel[0])
    need(not target.scheme and not target.netloc and not target.query, 'unsafe redirect target')
    path = PurePosixPath(unquote(target.path))
    need(target.path and not path.is_absolute() and '..' not in path.parts
         and '\\' not in target.path and ':' not in target.path, 'unsafe redirect path')
    return doc[0], str(path), target.fragment or parts.fragment


def link_destination(page, href, site):
    redirect = internal_redirect(href)
    if redirect:
        doc, path, anchor = redirect
        return site / doc / path, unquote(anchor)
    parts = urlsplit(href)
    if parts.scheme == 'file':
        return Path(unquote(parts.path)), unquote(parts.fragment)
    if parts.scheme or parts.netloc:
        return None
    return (page.parent / unquote(parts.path)).resolve(), unquote(parts.fragment)


def check_evidence(source, evidence, *, installed=False):
    need(evidence.get('status') == 'passed' and evidence.get('xref_checked') is True,
         'expected successful real-xref evidence')
    need(not installed or evidence.get('installed_xref') is True,
         'expected installed-xref evidence')
    expected = {(row['name'], module) for row in source['definitions'] for module in row['exports']}
    targets = evidence.get('targets', [])
    actual = {(row['name'], row['module']) for row in targets}
    need(actual == expected and len(targets) == len(expected),
         'runtime target inventory differs from the Reference source mapping')
    links = source.get('tutorial_links', [])
    fields = ('manual', 'directory', 'label', 'tag')
    expected = {tuple(row[k] for k in fields) for row in links}
    found = evidence.get('tutorial_targets', [])
    actual = {tuple(row.get(k) for k in fields) for row in found}
    need(expected == actual and len(expected) == len(found),
         'runtime tutorial target inventory differs from source mapping')
    fields = ('chapter', 'filename', 'tag', 'label')
    expected = {tuple(row[k] for k in fields) for row in source.get('section_links', [])}
    found = evidence.get('section_targets', [])
    actual = {tuple(row.get(k) for k in fields) for row in found}
    need(expected == actual and len(expected) == len(found),
         'runtime section target inventory differs from source mapping')


def check_targets(site: Path, evidence: dict, *, quick=None, smoke=None):
    """Check exact Racket-resolved anchors, plus real identifier links from a caller."""
    site = site.resolve()
    cache = {}

    def read(path):
        path = path.resolve()
        need(path.is_file(), f'missing HTML target: {path}')
        if path not in cache:
            cache[path] = Page(path.read_text(encoding='utf-8'))
        return cache[path]

    expected = {}
    for row in evidence['targets']:
        path = safe_file(site, 'skia-reference/' + row['relative_path'])
        need(read(path).anchors[unquote(row['anchor'])] == 1,
             f'missing/duplicate definition anchor: {row["name"]}')
        expected[row['name']] = (path.resolve(), unquote(row['anchor']))
    for path in (site / 'skia-reference').rglob('*.html'):
        need(read(path).badlinks == 0, f'unresolved Reference markup: {path}')
    probes = []
    if quick:
        probes.append((quick, ('make-surface', 'surface-canvas', 'make-paint',
                               'draw-rect', 'save-png', 'with-skia')))
    if smoke:
        for row in evidence['targets']:
            if row.get('module', 'skia') != 'skia':
                prefix = row['module'].removeprefix('skia/').replace('/', '-')
                expected[prefix + ':' + row['name']] = expected[row['name']]
        probes.append((smoke, tuple(expected)))
    counts = {}
    for path, names in probes:
        parsed = read(path)
        for name in names:
            matches = [(href, text) for href, text in parsed.links
                       if text.strip().replace('\u200b', '') == name]
            need(matches, f'missing identifier link {name} in {path}')
            for href, _ in matches:
                target = link_destination(path, href, site)
                need(target is not None and (target[0].resolve(), target[1]) == expected[name],
                     f'wrong binding link for {name}: {href}')
            counts[f'{path.name}:{name}'] = len(matches)
    tutorial_counts = {}
    reference_pages = sorted((site / 'skia-reference').rglob('*.html'))
    for row in evidence.get('tutorial_targets', []):
        directory = row['directory']
        need(re.fullmatch(r'skia-tutorials|skia-tutorial-[a-z-]+', directory),
             'invalid tutorial target directory')
        target = safe_file(site, directory + '/' + row['relative_path'])
        parsed_target = read(target)
        anchor = unquote(row['anchor'])
        need(not anchor or parsed_target.anchors[anchor] == 1, 'missing tutorial target anchor')
        count = 0
        for path in reference_pages:
            for href, text in read(path).links:
                if ' '.join(text.split()) != row['label']:
                    continue
                destination = link_destination(path, href, site)
                need(destination is not None
                     and (destination[0].resolve(), destination[1]) == (target.resolve(), anchor),
                     f'wrong tutorial link for {row["label"]}: {href}')
                count += 1
        need(count, f'missing tutorial link: {row["label"]}')
        tutorial_counts[row['directory']] = count
    section_counts = {}
    for row in evidence.get('section_targets', []):
        need(row['relative_path'] == row['filename'], 'section filename changed')
        target = safe_file(site, 'skia-reference/' + row['relative_path'])
        anchor = unquote(row['anchor'])
        parsed_target = read(target)
        need(not anchor or parsed_target.anchors[anchor] == 1,
             'missing/duplicate section anchor')
        count = 0
        if smoke:
            for href, text in read(smoke).links:
                if ' '.join(text.split()) != row['label']:
                    continue
                destination = link_destination(smoke, href, site)
                need(destination is not None
                     and (destination[0].resolve(), destination[1]) == (target.resolve(), anchor),
                     f'wrong section link for {row["tag"]}: {href}')
                count += 1
            need(count, f'missing section link: {row["tag"]}')
        section_counts[row['tag']] = dict(filename=row['filename'], anchor=anchor, links=count)
    return dict(status='passed', definition_anchors=len(evidence['targets']), links=counts,
                tutorial_links=tutorial_counts, section_links=section_counts)


def prepare_site(site: Path, *, source_root: Path | None = None):
    """Relocate known inter-manual redirects; never invent identifier destinations."""
    site = site.resolve()
    edits = 0
    pattern = re.compile(r'(href\s*=\s*")([^"]*)(")', re.I)
    for page in sorted(site.rglob('*.html')):
        source = page.read_text(encoding='utf-8')

        def replace(match):
            nonlocal edits
            target = internal_redirect(match[2])
            if not target and source_root is not None:
                parts = urlsplit(unescape(match[2]))
                if parts.scheme == 'file':
                    original = Path(unquote(parts.path)).resolve()
                    if original.is_relative_to(source_root.resolve()):
                        relative = original.relative_to(source_root.resolve())
                        if (len(relative.parts) >= 2
                            and re.fullmatch(r'skia-reference|skia-tutorials|skia-tutorial-[a-z-]+',
                                             relative.parts[0])):
                            target = (relative.parts[0], Path(*relative.parts[1:]).as_posix(),
                                      parts.fragment)
            if not target:
                return match[0]
            doc, path, anchor = target
            destination = safe_file(site, doc + '/' + path)
            need(destination.is_file(), f'uncopied manual target: {destination}')
            relative = Path(os.path.relpath(destination, page.parent)).as_posix()
            if anchor:
                relative += '#' + anchor
            edits += 1
            return match[1] + escape(relative, quote=True) + match[3]

        changed = pattern.sub(replace, source)
        if changed != source:
            page.write_text(changed, encoding='utf-8')
    return edits
