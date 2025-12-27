**NIXOS INSTALLATION:**

In your `flake.nix`, add this input: `mesa-git.url = "github:powerofthe69/portable-mesa-git-nix";`

Add the module: `mesa-git.nixosModules.default`

Enable this overlay: `nixpkgs.overlays = [ mesa-git.overlays.default ];` # module will not work otherwise

Activate the module and enjoy: `drivers.mesa-git.enable = true;`

It *should* theoretically pick up the Cachix configuration automatically.

All others can download the tarball from the releases page.

**Background**

This repo was created for personal use, or use by those on NixOS or those using Nix package manager. I say this because I made this specifically for ingesting in a sister repo that I'm using as a Nix flake, thus I can't be sure of the functionality on other platforms.

The idea was to have a mesa-git build run every night against the latest commit at the time of execution and create a tarball that includes the latest LLVM and other important libraries. This was originally being compiled on Ubuntu because it would imitate the environment that Steam Linux Runtime is built against - however, I found that FSR 4 was not working reliably. Instead of going through the trouble of continuing to troubleshoot Ubuntu and figure out what I did wrong, or if it was even able to be fixed, I refactored entirely into Nix. Originally I was going to only supply the tarball artifacts, but now I've added a whole module for NixOS installation. Mostly because FSR 4 WAS working previously, but was NOT working after an update and I have no idea why that is. So I decided to bite the bullet, figure out how Cachix works, and get this working.... Hopefully for good. Anyway - this took a lot of inspiration from Chaotic-Nyx, I trimmed some fat, and (for my personal preference) I added the git commit hash to the version string because I get the feel goods seeing those numbers go up on MangoHud.

HOWEVER, I'm bundling a tarball still with Nix's LLVM libraries. I know I said the FSR 4 isn't reliably working, but that could be just a NixOS thing... and some might say that having a tarball is better than not having a tarball, no? Also - while this may build nightly, main will only be merged with the latest successful build from this repo every Wednesday at 6AM UTC (1AM EST). Helps prevent shaders from being obsolete a day later (I have a script that runs on my local to remove shaders if a driver update is detected), and gives time in case a bug was introduced in a build from Friday, yet fixed in a build on Monday. Although, mesa-git is of course a "use-at-your-own-risk" driver, so I'm sure everyone is aware of these potential issues... If a broken build DOES find its way in, this has a fallback like Chaotic that will allow you to boot into your current derivation using the Stable driver. I hope that's bulletproof.

Now onto the reason this exists: Chaotic-Nyx was archived a short while ago, and provided mesa-git to NixOS on the system-level. I hadn't cared at first, but I had crashes on Mesa 25.3.2 when trying to play Monster Hunter Wilds (9070 XT, 9950X3D - if you have a similar build) and decided I'd try my hand at vibe coding this to fix the issue.

My initial thoughts were simple; I knew from past experience that different versions of Mesa could be pointed at by setting the VK_ICD_FILENAMES variable. This meant that the package didn't NEED to be built against Nix's libraries or integrated with the system. Or at least, I thought so, but I was unable to get native FSR 4 working in a reproducible manner. The tarball still exists and will not replace the system-level stable Mesa, but I added a module and now I'm self-hosting a Nix cache and Github runner on a local server. Hopefully this approach will fix native FSR 4 forever since I won't be moving the driver outside of a Nix derivation... because using FSR 3.1 is a fate worse than death.

Disclaimer: I'm not super smart or knowledgeable about this stuff, so most of this was done with trial and error alongside Gemini and Claude. If there are inefficiencies or areas of improvement, please submit a PR to fix them. Thank you!
