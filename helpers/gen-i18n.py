#!/usr/bin/env python3
import configparser
import json
import sys

from pathlib import Path
from os import path

class encoder(json.JSONEncoder):
	def default(self, o):
		d: dict = {}
		# underscores should be hyphens...
		for key in o.__dict__:
			d[key.replace('_', '-')] = o.__dict__.get(key)
		return d

class AOSCVariantTranslation:
	def __init__(self, name_tr: str, desc_tr: str, name_en: str, desc_en: str):
		self.dict = {
			name_tr: name_en,
			desc_tr: desc_en
		}
		self.dict_empty = {
			name_tr: "",
			desc_tr: ""
		}

class AOSCDistroBulletin:
	def __init__(self, title: str, body: str, title_tr: str, body_tr: str):
		self.dict = {}
		self.dict[title_tr] = title
		self.dict[body_tr] = body

def gen_manifest_i18n(i18n_dir: str):
	dir = Path(i18n_dir)
	catalog = {}

	if not dir.is_dir():
		print(f"[!] {i18n_dir} is either nonexistant or not a directory.", file=sys.stderr)

	for child in dir.iterdir():
		if not child.is_file() or child.suffix != '.ini' or 'template' in child.name:
			continue

		lang = child.stem
		if '.' in lang:
			print(f"[!] Invalid file name '{child}', skipping.", file=sys.stderr)
			continue

		dataset = configparser.ConfigParser()
		dataset.read(child)
		if not dataset.has_section('i18n'):
			print(f"[!] INI file '{child}' does not contain i18n data, skipping.", file=sys.stderr)
			continue

		cur_lang = {}
		cur_dataset = dataset['i18n']
		for key in cur_dataset.keys():
			cur_lang[key] = cur_dataset.get(key)

		catalog[lang] = cur_lang

	with open(f'{i18n_dir}/recipe-i18n.json', 'w') as f:
		json.dump(catalog, f)

def gen_i18n_template(outdir: str, recipe: str):
	dataset = configparser.ConfigParser()
	dataset.read(recipe)
	if 'bulletin' not in dataset:
		print("[!] Dataset provided is invalid: lacks [bulletin] section.", file=sys.stderr)
		exit(1)

	variants = []
	bulletin_data = dataset['bulletin']
	bulletin = AOSCDistroBulletin(bulletin_data['title'], bulletin_data['body'], bulletin_data['title-tr'], bulletin_data['body-tr'])
	for sec in dataset.sections():
		section = dataset[sec]
		if 'name-tr' not in section:
			continue
		obj = AOSCVariantTranslation(section['name-tr'], section['desc-tr'], section['name'], section['desc'])
		variants.append(obj)

	print("[+] Creating base translation (English) ...", file=sys.stderr)
	with open(f'{outdir}/en.ini', 'w') as f:
		catalog = {}
		catalog.update(bulletin.dict)
		for v in variants:
			catalog.update(v.dict)
		catalog = { "i18n": catalog }
		dataset = configparser.ConfigParser()
		dataset.read_dict(catalog)
		dataset.write(f)

def main():
	if len(sys.argv) != 4:
		print("ERROR: Path to the recipe.ini file and output directory required", file=sys.stderr)
		print(f"Usage: {sys.argv[0]} path/to/recipe.ini path/to/i18n-dir gen-template | gen-manifest")
		sys.exit(1)

	ini_file = sys.argv[1]
	outdir = sys.argv[2]
	action = sys.argv[3]

	match action:
		case "gen-template":
			gen_i18n_template(outdir, ini_file)
		case "gen-manifest":
			gen_manifest_i18n(outdir)
		case _:
			print("[!] Invalid usage.", file=sys.stderr)
			exit(1)

if __name__ == '__main__':
	main()
