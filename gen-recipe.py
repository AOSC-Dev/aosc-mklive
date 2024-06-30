#!/usr/bin/env python3
import configparser
import json
import os
import sys

from datetime import date
from typing import Optional

class encoder(json.JSONEncoder):
	def default(self, o):
		d: dict = {}
		# underscores should be hyphens...
		for key in o.__dict__:
			d[key.replace('_', '-')] = o.__dict__.get(key)
		return d


class AOSCRecipe:
	def __init__(self):
		self.ver: int = 1
		self.bulletin: 'AOSCRecipeBulletin' = AOSCRecipeBulletin()
		self.variants: list['AOSCRecipeVariant'] = []
		self.mirrors: list = []


class AOSCRecipeBulletin:
	def __init__(self):
		self.type: str = "info"
		self.title: str = "Thank You for Choosing AOSC OS"
		self.title_tr: str = "bulletin-title"
		self.body: str = "AOSC OS strives to simplify your user experience and improve your day-to-day productivity."
		self.body_tr: str = "bulletin-body"


class AOSCRecipeVariant:
	def __init__(self, name: str, name_tr: str, retro: bool,
		     desc: str, desc_tr: str, dir_name: str):
		self.name: str = name
		self.name_tr: str = name_tr
		self.retro: bool = retro
		self.description: str = desc
		self.description_tr: str = desc_tr
		self.dir_name: str = dir_name
		self.tarballs: list = []
		self.squashfs: list['AOSCSquashfsSpec'] = []


class AOSCSquashfsSpec:
	def __init__(self, arch: str, instSize: int, path: str,
		 inodes: int, downloadSize: int = 0, sha256sum: str = ""):
		self.arch: str = arch
		self.downloadSize: int = downloadSize
		self.instSize: int = instSize
		self.path: str = path
		self.sha256sum: str = ""
		self.inodes: int = inodes
		self.date = date.today().strftime('%Y%m%d')


class AOSCOfflineSysrootSpec:
	def __init__(self, arch: str, instSize: int, path: str,
		 inodes: int):
		self.arch: str = arch
		self.instSize: int = instSize
		self.path: str = path
		self.inodes: int = inodes


def main():
	if len(sys.argv) < 3:
		print("ERROR: Path to the generated INI file and the output file must be provided.", file=sys.stderr)
		print(f"Usage: {sys.argv[0]} ini_file output", file=sys.stderr)
		sys.exit(1)
	ini_file = sys.argv[1]
	output_file = sys.argv[2]
	if not os.path.exists(os.path.realpath(ini_file)):
		print(f"ERROR: INI file {ini_file} does not exist.", file=sys.stderr)
		sys.exit(1)
	arch = ''
	if 'ARCH' in os.environ:
		arch = os.environ['ARCH']
	else:
		import subprocess
		arch = subprocess.getoutput('dpkg --print-architecture')
	dataset = configparser.ConfigParser()
	dataset.read('recipe.ini')
	archs = dataset.get('recipe', 'archs').split()
	if arch not in archs:
		print(f"ERROR: Specified target {arch} looks like an invalid one.")
		sys.exit(1)
	data = configparser.ConfigParser()
	data.read(ini_file)
	sysroots = data.get('installer', 'sysroots').split()
	recipe = AOSCRecipe()
	for variant in sysroots:
		if variant not in dataset.sections():
			print(f"ERROR: Variant {variant} not present in recipe.ini.")
			sys.exit(1)
		if variant not in data.sections():
			print(f"ERROR: Variant {variant} not present in {ini_file}.")
			print(f"       Make sure your sysroots match the sections.")
			sys.exit(1)
		cur_variant = dataset[variant]
		cur_sysroot = data[variant]
		sysroot_obj = AOSCSquashfsSpec(arch, int(cur_sysroot['installedsize']),
			f'/run/livekit/sysroots/{variant}', int(cur_sysroot['inodes']))
		cur_variant_obj = AOSCRecipeVariant(cur_variant['name'], cur_variant['name-tr'],
				True if cur_variant['retro'] == 'true' else False,
				cur_variant['desc'], cur_variant['desc-tr'], cur_variant['dir-name'])
		cur_variant_obj.squashfs.append(sysroot_obj)
		recipe.variants.append(cur_variant_obj)
	print("Generated JSON:")
	print(encoder().encode(recipe))
	print(f"Saving to {output_file} ...")
	with open(output_file, 'w+') as of:
		json.dump(recipe, of, cls=encoder)


if __name__ == '__main__':
	main()
