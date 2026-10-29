# nxnative

Play your own Nintendo Switch games natively on iPhone and iPad. Bring your game (its NSP files) and your `prod.keys`; one script turns them into an IPA that you sideload.

It is not an emulator: the game's own code runs directly on the Apple chip, with Switch graphics rebuilt on Metal. Nothing from any game is in this repository, and the project is not affiliated with Nintendo or any game publisher.

## How to play

### With a Mac app

Community projects build on nxnative with Mac apps that turn your games into apps for your iPhone, iPad or Mac, with no command line, and keep them in a library. They are separate projects: questions and bugs about them go to their own pages.

- [NX2Apple](https://github.com/LNPANDY/NX2Apple)
- [NX Play](https://github.com/varyform/nx-native-wrapper)
- [NxNative Launcher](https://github.com/rennan101/nxnative_Launcher)

### Build from the command line

You need a Mac with macOS 26.6 or later, [Xcode](https://apps.apple.com/app/xcode/id497799835) 27.1, [Homebrew](https://brew.sh) and Python 3.12 or newer (an arm64 one, not an Intel Homebrew's). An iPhone build also needs Xcode's iOS platform (Xcode → Settings → Components).

**1. Install the tools** (only once), in Terminal:

```
xcodebuild -downloadComponent MetalToolchain
git clone https://github.com/seedds/nxnative.git && cd nxnative
brew install xcodegen zstd glslang
brew install --cask dotnet-sdk
python3 -m pip install lz4 capstone fonttools nsz zbic "backports.zstd; python_version < '3.14'"
```

**2. Put your game in a folder**: the game, plus its update and DLC if you have them (`.nsp`, `.xci`, `.nsz` or `.xcz`):

```
~/Games/MarioWonder/
  Super Mario Bros. Wonder [010015100B514000][v0].nsp
  Super Mario Bros. Wonder [010015100B514800][v327680].nsp
```

**3. Build**, with your game folder and your `prod.keys`:

```
python3 scripts/build_ipa_from_nsp.py ~/Games/MarioWonder -k ~/keys/prod.keys
```

The IPA appears in the game's folder. The first build takes 30–60 minutes and needs free disk space of about twice the game's size plus 10 GB; building again is much faster.

To play on the Mac instead, add `--platform mac-app`: you get a Mac app of the game to open from Finder. All options: [The packing script in detail](docs/development.md#the-packing-script-in-detail).

### Install

Install the IPA on your iPhone or iPad with a sideloading tool such as AltStore, Sideloadly or LiveContainer. If your tool offers **Increased Memory Limit**, turn it on: the bigger games need it.

Game too big to install? Build again with `--romfs separate`, and run the command the script prints once to copy the game files to your phone ([Quick reinstalls](docs/development.md#quick-reinstalls)).

Controls, saves and settings: [Playing](docs/playing.md).

## Games

Games tested on Mac or iPhone. See the [per-game notes](dm/games/README.md#games) for tested platforms, progress and known issues:

Needs iOS / iPadOS 26 or later on an iPhone 15 Pro or newer (A17 Pro chip or later) or an iPad with an M1 chip or later: the games' textures are BC-compressed, and older iPhones can't read that format. Other games aren't supported yet. For them the script writes a survey and still tries its best to pack an IPA, guessing the game's settings; such an IPA may not start.

After a game, "60 fps with 1.2.0" means it runs at 60 fps (30 on the Switch) with that update.

<!-- games list: written by dm/tools/docs_games.py from docs/games.tsv; change the table, then run it -->
- [Mario Kart 8 Deluxe](dm/games/0100152000022000/README.md) — no Mii heads
- [Mario vs. Donkey Kong](dm/games/0100B99019412000/README.md)
- [Paper Mario: The Thousand-Year Door](dm/games/0100ECD018EBE000/README.md) — 60 fps with 1.0.1
- [Super Mario 3D World + Bowser's Fury](dm/games/010028600EBDA000/README.md)
- [Super Mario Bros. Wonder](dm/games/010015100B514000/README.md)
- [Super Mario Galaxy](dm/games/010099C022B96000/README.md)
- [Super Mario Galaxy 2](dm/games/0100FD8022DAA000/README.md)
- [Super Mario Odyssey](dm/games/0100000000010000/README.md)
- [The Legend of Zelda: Breath of the Wild](dm/games/01007EF00011E000/README.md) — 60 fps with 1.9.0
- [The Legend of Zelda: Link's Awakening](dm/games/01006BB00C6F0000/README.md)
- [The Legend of Zelda: Tears of the Kingdom](dm/games/0100F2C0115B6000/README.md) — 60 fps with 1.4.3
- [13 Sentinels: Aegis Rim](dm/games/01003FC01670C000/README.md)
- [Absolum](dm/games/0100A83022A22000/README.md)
- [Ace Attorney Investigations Collection](dm/games/010005501E68C000/README.md)
- [Advance Wars 1+2: Re-Boot Camp](dm/games/0100300012F2A000/README.md)
- [AI: THE SOMNIUM FILES](dm/games/010089B00D09C000/README.md)
- [AI: THE SOMNIUM FILES - nirvanA Initiative](dm/games/0100713016CCC000/README.md)
- [Animal Crossing: New Horizons](dm/games/01006F8002326000/README.md)
- [ANIMAL WELL](dm/games/010020D01AD24000/README.md)
- [ASTRAL CHAIN](dm/games/01007300020FA000/README.md) — 60 fps target with 1.0.1
- [Balatro](dm/games/0100CD801CE5E000/README.md) — played by touch
- [BALL x PIT](dm/games/010086A022444000/README.md)
- [Bayonetta](dm/games/010076F0049A2000/README.md)
- [Bayonetta 2](dm/games/01007960049A0000/README.md)
- [Bayonetta 3](dm/games/01004A4010FEA000/README.md)
- [Big Brain Academy: Brain vs. Brain](dm/games/0100620012D6E000/README.md)
- [Brain Memory Training Academy](dm/games/0100F5D01DA3A000/README.md)
- [Captain Toad: Treasure Tracker](dm/games/01009BF0072D4000/README.md)
- [Catherine: Full Body](dm/games/0100BF00112C0000/README.md)
- [Celeste](dm/games/01002B30028F6000/README.md)
- [Cuphead](dm/games/0100A5C00D162000/README.md)
- [DARK SOULS: REMASTERED](dm/games/01004AB00A260000/README.md) — 60 fps with 1.0.3
- [Digimon Story Cyber Sleuth: Complete Edition](dm/games/010014E00DB56000/README.md)
- [Donkey Kong Country: Tropical Freeze](dm/games/0100C1F0051B6000/README.md)
- [DRAGON QUEST VII Reimagined](dm/games/0100A9D01C446000/README.md)
- [DRAGON QUEST XI S: Echoes of an Elusive Age – Definitive Edition](dm/games/01006C300E9F0000/README.md) — 60 fps with 1.0.4
- [FINAL FANTASY RESONANCE](dm/games/0100606026F12000/README.md) — 60 fps with 1.0.1
- [FINAL FANTASY TACTICS - The Ivalice Chronicles](dm/games/010038B015560000/README.md)
- [Fire Emblem Engage](dm/games/0100A6301214E000/README.md) — 60 fps with 2.0.0
- [Fire Emblem: Three Houses](dm/games/010055D009F78000/README.md) — 60 fps with 1.2.0
- [Ghost Trick: Phantom Detective](dm/games/010029B018432000/README.md)
- [The Great Ace Attorney Chronicles](dm/games/010036E00FB20000/README.md)
- [Hades](dm/games/0100535012974000/README.md)
- [Hades II](dm/games/0100A00019DE0000/README.md)
- [Hollow Knight: Silksong](dm/games/010013C00E930000/README.md)
- [Hyrule Warriors: Age of Calamity](dm/games/01002B00111A2000/README.md) — 60 fps with 1.3.0
- [Kirby and the Forgotten Land](dm/games/01004D300C5AE000/README.md)
- [Luigi's Mansion 3](dm/games/0100DCA0064A6000/README.md) — 60 fps with 1.4.0
- [Metroid Dread](dm/games/010093801237C000/README.md)
- [Monster Hunter Rise](dm/games/0100B04011742000/README.md) — 60 fps with 16.0.2
- [Monster Train 2](dm/games/010051701FB46000/README.md) — 60 fps with 1.1.1
- [OCTOPATH TRAVELER](dm/games/010057D006492000/README.md)
- [Octopath Traveler 0](dm/games/01005270232F2000/README.md) — 60 fps with 1.0.5
- [Octopath Traveler II](dm/games/0100A3501946E000/README.md) — 60 fps with 1.1.1
- [Patrick's Parabox](dm/games/0100E44016C22000/README.md)
- [Persona 5 Royal](dm/games/01005CA01580E000/README.md)
- [Pikmin 4](dm/games/0100B7C00933A000/README.md)
- [Pokémon Brilliant Diamond](dm/games/0100000011D90000/README.md) — 60 fps with 1.3.0
- [Pokémon Legends: Z-A](dm/games/0100F43008C44000/README.md)
- [Pokémon Scarlet](dm/games/0100A3D008C5C000/README.md)
- [Pokémon Sword](dm/games/0100ABF008968000/README.md)
- [Pokémon Shield](dm/games/01008DB008C2C000/README.md)
- [Portal](dm/games/01007BB017812000/README.md)
- [Raging Loop](dm/games/010020400E1C2000/README.md)
- [Rhythm Heaven Groove](dm/games/0100D9F01D474000/README.md)
- [ROMANCE OF THE THREE KINGDOMS 8 REMAKE](dm/games/0100C2A01A730000/README.md) — controller only
- [Sea of Stars](dm/games/01008C0016544000/README.md)
- [SHIN MEGAMI TENSEI V: Vengeance](dm/games/010069C01AB82000/README.md) — 60 fps with 1.0.3
- [Stardew Valley](dm/games/0100E65002BB8000/README.md)
- [STEINS;GATE RE:BOOT](dm/games/01008BC024FDE000/README.md)
- [Super Smash Bros. Ultimate](dm/games/01006A800016E000/README.md) — offline
- [Taiko Risshiden V DX](dm/games/0100346017304000/README.md) — Japanese · played by touch
- [Unicorn Overlord](dm/games/010069401ADB8000/README.md)
- [Yoshi's Crafted World](dm/games/01006000040C2000/README.md)
- [NieR:Automata The End of YoRHa Edition](dm/games/010056B015FE8000/README.md) — 60 fps with 1.0.3
- [The Legend of Zelda: Echoes of Wisdom](dm/games/01008CF01BAAC000/README.md)
- [Donkey Kong Country Returns HD](dm/games/01009D901BC56000/README.md)
- [Mario + Rabbids Sparks of Hope](dm/games/0100317013770000/README.md)
- [Xenoblade Chronicles 2](dm/games/0100E95004038000/README.md)
- [Xenoblade Chronicles 3](dm/games/010074F013262000/README.md)
- [FINAL FANTASY CRYSTAL CHRONICLES Remastered Edition](dm/games/0100CE4010AAC000/README.md)
- [Return of the Obra Dinn](dm/games/010032E00E6E2000/README.md)
- [Blasphemous 2](dm/games/010040801A4C8000/README.md)
- [Silver Pines](dm/games/0100D5B026844000/README.md)
- [Blasphemous](dm/games/0100698009C6E000/README.md)
- [FINAL FANTASY X/X-2 HD Remaster](dm/games/0100BC300CB48000/README.md)
- [Mario + Rabbids Kingdom Battle](dm/games/010067300059A000/README.md)
- [Persona 4 Golden](dm/games/010062B01525C000/README.md)
- [Xenoblade Chronicles: Definitive Edition](dm/games/0100FF500E34A000/README.md)
- [Pokémon Legends: Arceus](dm/games/01001F5010DFA000/README.md)
- [Super Mario Party Jamboree](dm/games/0100965017338000/README.md)
- [Cult of the Lamb](dm/games/01002E7016C46000/README.md)
- [Paper Mario: The Origami King](dm/games/0100A3900C3E2000/README.md)
- [Batman: Arkham Knight](dm/games/0100ACD0163D0000/README.md)
- [Bastion](dm/games/010038600B27E000/README.md)
- [Baba Is You](dm/games/01002CD00A51C000/README.md)
- [SteamWorld Heist II](dm/games/010089C01E9CA000/README.md)
- [SteamWorld Heist: Ultimate Edition](dm/games/010016100A186000/README.md)
- [Subnautica: Below Zero](dm/games/010014C011146000/README.md)
- [SteamWorld Dig 2](dm/games/0100CA9002322000/README.md)
- [Streets of Rage 4](dm/games/0100EC9010258000/README.md)
- [Mario Party Superstars](dm/games/01006FE013472000/README.md)
- [Subnautica](dm/games/0100429011144000/README.md)
- [SteamWorld Dig](dm/games/01009320084A4000/README.md)
- [Team Sonic Racing](dm/games/010092B0091D0000/README.md)
- [Well Dweller](dm/games/0100217023F6C000/README.md)
- [Need for Speed: Hot Pursuit Remastered](dm/games/010029B0118E8000/README.md)
<!-- end of games list -->

### For developers

[How it works](docs/development.md) · [Game notes](dm/games/README.md#games) · [Bring-up and debugging](docs/agents/README.md) · [Front ends](docs/frontends.md) · [Contributing](CONTRIBUTING.md)

### Acknowledgements

nxnative started from **[d2r-mobile](https://github.com/jhaizhou-ops/d2r-mobile)** (MIT), which developed this native-execution approach for Diablo II: Resurrected: its NSO rewriter, Horizon host, NVN-on-Metal layer and iOS app shell. Fixes go both ways. It also builds on **Ryujinx** (MIT; its shader translator, in `dm/third_party/ryujinx` with [a few fixes](dm/third_party/ryujinx/README.md), and a reference for system services), **[Atmosphère](https://github.com/Atmosphere-NX/Atmosphere)** (Horizon's synchronization semantics), **yuzu** (Maxwell encodings, kernel cross-checks), **[LibHac](https://github.com/Thealexbarney/LibHac)** and **hactool** (reading NSPs), **[SPIRV-Cross](https://github.com/KhronosGroup/SPIRV-Cross)** and **[glslang](https://github.com/KhronosGroup/glslang)** (shaders to Metal), **deko3d** (zlib; texture layout sizes), **libvpx**, **stb_vorbis**, the **Vulkan headers** and **NVIDIA FLIP** ([licenses](dm/third_party/README.md)), and **Capstone**, **lz4**, **fontTools** and **XcodeGen** in the build.

### License

MIT ([LICENSE](LICENSE)). Third-party code keeps its own license ([dm/third_party](dm/third_party/README.md)).
