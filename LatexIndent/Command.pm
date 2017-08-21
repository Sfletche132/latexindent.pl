package LatexIndent::Command;
#	This program is free software: you can redistribute it and/or modify
#	it under the terms of the GNU General Public License as published by
#	the Free Software Foundation, either version 3 of the License, or
#	(at your option) any later version.
#
#	This program is distributed in the hope that it will be useful,
#	but WITHOUT ANY WARRANTY; without even the implied warranty of
#	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#	GNU General Public License for more details.
#
#	See http://www.gnu.org/licenses/.
#
#	Chris Hughes, 2017
#
#	For all communication, please visit: https://github.com/cmhughes/latexindent.pl
use strict;
use warnings;
use LatexIndent::Tokens qw/%tokens/;
use LatexIndent::TrailingComments qw/$trailingCommentRegExp/;
use LatexIndent::Switches qw/$is_t_switch_active $is_tt_switch_active/;
use LatexIndent::GetYamlSettings qw/%masterSettings/;
use Data::Dumper;
use Exporter qw/import/;
our @ISA = "LatexIndent::Document"; # class inheritance, Programming Perl, pg 321
our @EXPORT_OK = qw/construct_command_regexp $commandRegExp $commandRegExpTrailingComment $optAndMandAndRoundBracketsRegExpLineBreaks/;
our $commandCounter;
our $commandRegExp;
our $commandRegExpTrailingComment; 
our $optAndMandAndRoundBracketsRegExp; 
our $optAndMandAndRoundBracketsRegExpLineBreaks; 

# store the regular expresssion for matching and replacing 
sub construct_command_regexp{
    my $self = shift;

    $optAndMandAndRoundBracketsRegExp = $self->get_arguments_regexp(
                                                                    roundBrackets=>${$masterSettings{commandCodeBlocks}}{roundParenthesesAllowed},
                                                                    stringBetweenArguments=>1);

    $optAndMandAndRoundBracketsRegExpLineBreaks = $self->get_arguments_regexp(
                                                                    roundBrackets=>${$masterSettings{commandCodeBlocks}}{roundParenthesesAllowed},
                                                                    mode=>"lineBreaksAtEnd",
                                                                    stringBetweenArguments=>1);

    # put together a list of the special command names (this was mostly motivated by the \@ifnextchar[ issue)
    my %commandNameSpecial = %{${$masterSettings{commandCodeBlocks}}{commandNameSpecial}};

    my $commandNameSpecialRegExp = q();
    while( my ($commandName,$yesNo)= each %commandNameSpecial){
        # change + and - to escaped characters
        $commandName =~ s/\+/\\+/g;
        $commandName =~ s/\-/\\-/g;
        $commandName =~ s/\[/\\[/g;

        # form the regexp
        $commandNameSpecialRegExp .= ($commandNameSpecialRegExp eq '' ? q() : "|").$commandName if $yesNo; 
    }

    # details to log file
    $self->logger("The special command names regexp is: $commandNameSpecialRegExp (see commandNameSpecial)",'heading') if $is_t_switch_active;

    # construct the command regexp
    $commandRegExp = qr/
              (\\|\\@|@)   
              (
               [+a-zA-Z@\*0-9_\:]+?|$commandNameSpecialRegExp      # lowercase|uppercase letters, @, *, numbers
              )                
              (\h*)
              (\R*)?
              ($optAndMandAndRoundBracketsRegExp)
              (\R)?
            /sx;

    # command regexp with trailing comment
    $commandRegExpTrailingComment = qr/$commandRegExp(\h*)((?:$trailingCommentRegExp\h*)*)/;

}

sub tasks_particular_to_each_object{
    my $self = shift;

    # check for adding/removing linebreaks before =
    $self->check_linebreaks_before_equals;

    # search for arguments
    $self->find_opt_mand_arguments;

    # situation: ${${$self}{linebreaksAtEnd}}{end} == 1, and the argument container object
    # still contains a linebreak at the end; in this case, we need to remove the linebreak from 
    # the container object
    if(${${$self}{linebreaksAtEnd}}{end} == 1 
      and ${${${$self}{children}}[0]}{body} =~ m/\R$/s
      and !${$self}{endImmediatelyFollowedByComment}){
        $self->logger("Removing linebreak from argument container of ${$self}{name}") if $is_t_switch_active;
        ${${${$self}{children}}[0]}{body} =~ s/\R$//s;
        ${${${${$self}{children}}[0]}{linebreaksAtEnd}}{body} = 0;
    }

    # situation: ${${$self}{linebreaksAtEnd}}{end} == 1 and the last argument specifies
    # EndFinishesWithLineBreaks = 0 (see test-cases/commands/just-one-command-mod10.tex)
    if(${${$self}{linebreaksAtEnd}}{end} == 1 
        and defined ${${${${$self}{children}}[0]}{children}[-1]}{EndFinishesWithLineBreak} 
        and ${${${${$self}{children}}[0]}{children}[-1]}{EndFinishesWithLineBreak} == -1
        ){
          $self->logger("Switching linebreaksAtEnd{end} to be 0 in command ${$self}{name} as last argument specifies EndFinishesWithLineBreak == 0") if $is_t_switch_active;
          ${${$self}{linebreaksAtEnd}}{end} = 0;
          ${$self}{EndFinishesWithLineBreak} = -1;
        }
    
    # if the last argument finishes with a linebreak, it won't get interpreted at 
    # the right time (see test-cases/commands/commands-one-line-nested-simple-mod1.tex for example)
    # so this little bit fixes it
    if(${${${${${$self}{children}}[0]}{children}[-1]}{linebreaksAtEnd}}{end} and ${${$self}{linebreaksAtEnd}}{end} == 0 
        and defined ${${${${$self}{children}}[0]}{children}[-1]}{EndFinishesWithLineBreak} 
        and ${${${${$self}{children}}[0]}{children}[-1]}{EndFinishesWithLineBreak} >= 1 
        and !${$self}{endImmediatelyFollowedByComment}){

        # update the Command object
        $self->logger("Adjusting linebreaksAtEnd in command ${$self}{name}") if $is_t_switch_active;
        ${${$self}{linebreaksAtEnd}}{end} = ${${${${${$self}{children}}[0]}{children}[-1]}{linebreaksAtEnd}}{end};
        ${$self}{replacementText} .= "\n";

        # if the last argument has EndFinishesWithLineBreak == 3
        if (${${${${$self}{children}}[0]}{children}[-1]}{EndFinishesWithLineBreak} == 3 ){
              my $EndStringLogFile = ${${${${$self}{children}}[0]}{children}[-1]}{aliases}{EndFinishesWithLineBreak}||"EndFinishesWithLineBreak";
              $self->logger("Adding another blank line to replacement text for ${$self}{name} as last argument has $EndStringLogFile == 3 ") if $is_t_switch_active;
              ${$self}{replacementText} .= (${$masterSettings{modifyLineBreaks}}{preserveBlankLines}?$tokens{blanklines}:"\n")."\n";
        }

        # update the argument object
        $self->logger("Adjusting argument object in command, ${$self}{name}") if $is_t_switch_active;
        ${${${${$self}{children}}[0]}{linebreaksAtEnd}}{body} = 0;
        ${${${$self}{children}}[0]}{body} =~ s/\R$//s;

        # update the last mandatory/optional argument
        $self->logger("Adjusting last argument in command, ${$self}{name}") if $is_t_switch_active;
        ${${${${${$self}{children}}[0]}{children}[-1]}{linebreaksAtEnd}}{end} = 0;
        ${${${${$self}{children}}[0]}{children}[-1]}{EndFinishesWithLineBreak} = -1;
        ${${${${$self}{children}}[0]}{children}[-1]}{replacementText} =~ s/\R$//s;

        # output to log file
        $self->logger(Dumper(${${${$self}{children}}[0]}{children}[-1])) if $is_t_switch_active;
    }

    # situation: ${${$self}{linebreaksAtEnd}}{end} == 1 and the last argument has added 
    # a line break, which can result in a bogus blank line (see test-cases/commands/just-one-command.tex with mand-args-mod1.yaml)
    if(${${$self}{linebreaksAtEnd}}{end} == 1 
        and defined ${${${${$self}{children}}[0]}{children}[-1]}{EndFinishesWithLineBreak} 
        and ${${${${$self}{children}}[0]}{children}[-1]}{EndFinishesWithLineBreak} >= 1 
        and ${${${${$self}{children}}[0]}{children}[-1]}{replacementText}=~m/\R$/s
        and !${$self}{endImmediatelyFollowedByComment}){
    
        # last argument adjustment
        $self->logger("Adjusting last argument in command, ${$self}{name} to avoid double line break") if $is_t_switch_active;
        ${${${${$self}{children}}[0]}{children}[-1]}{replacementText}=~s/\R$//s;
        ${${${${${$self}{children}}[0]}{children}[-1]}{linebreaksAtEnd}}{end} = 0;

        # argument object adjustment
        $self->logger("Adjusting argument object in command, ${$self}{name} to avoid double line break") if $is_t_switch_active;
        ${${${${$self}{children}}[0]}{linebreaksAtEnd}}{body} = 0;
        ${${${$self}{children}}[0]}{body}=~s/\R$//s;
    } 

    # the arguments body might finish with horizontal space, in which case, we need to transfer this 
    # to the parent object replacement text.
    #
    # see ../test-cases/texexchange/5461.tex which was the first example to demonstrate the need for this
    if(!${${${$self}{children}}[0]}{endImmediatelyFollowedByComment} and ${${${$self}{children}}[0]}{body} =~ m/\h*$/ and ${$self}{replacementText} !~ m/\R$/){
        $self->logger("${$self}{name}: trailling horizontal space found in arguments -- removing it from arguments, adding to replacement text") if $is_t_switch_active;
        ${${${$self}{children}}[0]}{body} =~ s/(\h*)$//s; 
        ${$self}{replacementText} .= "$1";
    }

    # search for ifElseFi blocks
    $self->find_ifelsefi;

    # search for special begin/end
    $self->find_special;

}

sub check_linebreaks_before_equals{
    # empty routine, which allows the above routine to function (this routine kicks in for KeyEqualsValuesBraces)
    return;
}

sub create_unique_id{
    my $self = shift;

    $commandCounter++;
    ${$self}{id} = "$tokens{commands}$commandCounter";
    return;
}

sub align_at_ampersand{
    # need an empty routine here for commands; see
    # test-cases/matrix1.tex for example
    return;
}

1;