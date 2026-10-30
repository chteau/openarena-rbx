/*
===========================================================================
Copyright (C) 2006 Dmn_clown (aka: Bob Isaac (rjisaac@gmail.com))

This file is part of Open Arena and is based upon Mr. Elusive's fuzzy logic
system found in Quake 3 Arena.

Open Arena is free software; you can redistribute it
and/or modify it under the terms of the GNU General Public License as
published by the Free Software Foundation; either version 2 of the License,
or (at your option) any later version.

Open Arena is distributed in the hope that it will be
useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Foobar; if not, write to the Free Software
Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
===========================================================================
*/

["no", "not", "Nada", "nope", !"no place", !"no feeling."] = 5
{
	"are you sure about that?";
	"You sound so sure of yourself";
	"Really?";
	"Don't be so certain";
}

["why", !"why not"] = 8
{
	"why not?";
	"because dmn_clown said!";
	"My ", counselor, " said so.";
	botnames, " said so.";
	confused_response;
	peeps, " said so.";
}

["what is happening?"] = 1
{
	"dork";
	"dweeb";
	"noob";
	"chump";
}

["ha", "LOL", "laugh", "funny"] = 6
{
	"I'm not laughing.";
	"What is so funny?";
	"That wasn't funny...";
	"Sorry, I forgot to laugh";
	immaturity01;
	"hehe";
	"That was amusing";
	"Ok, that was funny";
	response_insult;
}

["fishing", !"freak fishing"] = 3
{
	"My ", family_member, " was eaten by a blue whale last ", month, ".";
	"I like to use ", substance, " as bait, but only when it is ", weather, ".";
	"I'd swear that asian carp can speak ", language, ".";
	response_insult;
}

["humiliating", "shamed"] = 3
{
	"LOL!";
	"Hehe... good";
	"You deserve to be";
	"Merry x-mas!";
}

["why not"] = 6
{
	"because ", peeps, " said.";
	"because I said";
	"because dmn_clown said so!";
	"A ", profession, " said so.";
}

["yes", "sure", "certainly"] = 2
{
	confused_response;
	neutral;
	"You sound positive.";
	"You've convinced me.";
	"Ok";
	
}

[(1, " is a ", 0) &name, !"Grism", !"Gargoyle", !"Dmo", !"Penguin", !"Sarge", !"Grunt"] = 4
{
	"That is Mizz ", 0, " to you, ", fighter, ".";
	"I'm only rude to ", fighter, "s like you.";
}

["OI"] = 5
{
	"OI! OI! OI!";
}

["bots", "bot", !"stupid bot"] = 2
{
	"Heh... right!";
	"Bah!  Humbug...";
	"The correct term is 'human exterminator'";
	"What is that about?";
	"I frag, therefore I am.";
}

["stupid bot"] = 5
{
	"Yeah, bots are stupid.";
	"Man, why do they even bother with ai, it never works?";
	"Hey!  Blame the person that programmed me!";
	"What are you trying to say, Dave?";
}

[(1, " is a ", 0) &name, !"Kyonshi", !"Major", !"Hnt", !"Dark", !"Tanisha", !"Rai", !"Slshish"] = 4
{
	"That is Mr. ", 0, " to you, ", fighter, ".";
	"I'm only rude to ", fighter, "s like you.";
}

["meaning of it all"] = 5
{
	"Only what you give it.";
	"It?  It has no meaning, it just is.";
	"You think too much, shut up and frag.";
	"Has anyone ever told you to frag more and talk less?";
}

["Aardappel", "leileilol", "Multiplex", "crayon", "JK Makowka", "Democritus", "jzero", "Mancubus", "mewse", "div0", "MilesTeg", "evillair", "Shadowdragon", "mightypea", "Morphed", "toddd", "Psymong", "DarkThief", "slyus", "SavageX", "Kaz", "pixie", "Vondur", "Tyrann", "Ed", "Czestmyr", "kick52", "kit89", "lazureus", "sago007", "dmn_clown"] = 1
{
	"Why do you think you have the right to utter that name, you ", fighter, "?";
	"Speak that name with respect.";
	"You would be wise to respect the name you just uttered.";
	"Shh... The Arena Lords may be listening.";
	"I am not worthy to even think that name.";
	"Silence, Mortal!  You are not worthy of uttering an Arena Lord's name.";
}

[("sing me a song ", 0) &name] = 5
{
	"No, I am not in the mood.";
	"There must be someway out of here, said the joker to the thief...";
	"Hey, Mr. Tamberine man, play a song for me, I'm not sleepy and there ~ain't no place I'm going to...";
	"Not right now, I'm kinda busy.";
	"Sometimes I try to do things and it just don't turn out the way I want it to and I get real frustrated...";
	"... ~Don't go out tonight, it could be your life, ~there's a bathroom on the right...";
	"Play some Skynard, Man!";
	"Sorry, my voice is shot... too much yelling.";
	"Nah...";
	"La la la... I can't hear you over the rockets!";
}

