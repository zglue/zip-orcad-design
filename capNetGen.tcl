#////////////////////////////////////////
# Copyright 2020 zGlue, Inc.
#
# Licensed under zOH License version 1.0 ("the license") 
# that is included in the accompanying repository.
# You may not use this file except in compliance with the License.
# You may obtain a copy of the license at <zglue.com/oci/zohl1v>
#
# AUTHOR(S): Jorge L. Rojas
#
# DESCRIPTION: zGlue's OrCAD Capture TCL
# Utility to create SPICE netlists from 
# and OrCAD schematic that ChipBuilder 
# can consume to create a ZIP system.
#
#////////////////////////////////////////

package require DboTclWriteBasic 17.2.0
package provide capNetGen 1.0
namespace eval ::capNetGen {
    namespace export searchText
    namespace export replaceText
}


#############################
###   SPICE Netlist Gen   ###
#############################

proc ::capNetGen::generateNetlist { pOpenDesignName pOutFile } {
    # Verify Args
    puts $pOpenDesignName
    puts $pOutFile

    # init tcl session
    set lSession $::DboSession_s_pDboSession
    DboSession -this $lSession
    set lStatus [DboState]
    set lNullObj NULL

    # Const
    set pNetNameDelim ":"
    set pValueDelim   "_"
    set pSpaceDelim   " "

    # Vars
    set lInstCnt  1
    set pUConnId  32767

    set pSubCktDef ""
    set pNetlist   ""
    set lReference [DboTclHelper_sMakeCString ]
    set lValue     [DboTclHelper_sMakeCString ]
    set lPinNumber [DboTclHelper_sMakeCString ]
    set lPinName   [DboTclHelper_sMakeCString ]
    set lNetName   [DboTclHelper_sMakeCString ]

    # open output file
    set sysTime   [clock seconds]
    set timeStr   [clock format $sysTime -format %H:%M:%S]
    set dateStr   [clock format $sysTime -format %D]
    set netlistFP [open $pOutFile "w"]
    set pNetlistHeader "* Auto-Generated SPICE Netlist\n* Design: $pOpenDesignName\n* Date: $dateStr, Time: $timeStr\n"
    
    puts $netlistFP $pNetlistHeader

    # get design
    set lDesignName [DboTclHelper_sMakeCString $pOpenDesignName]
    set lDesign [$lSession GetOpenDesign $lDesignName $lStatus]
    # puts $lDesign

    # get schematic
    set pSchematicName SCHEMATIC1
    set lSchematicName [DboTclHelper_sMakeCString $pSchematicName]
    set lSchematic     [$lDesign GetSchematic $lSchematicName $lStatus]
    # puts $lSchematic

    # get page
    set lPagesIter [$lSchematic NewPagesIter $lStatus]
    set lPage      [$lPagesIter NextPage $lStatus]
    # puts $lPage

    while {$lPage != $lNullObj} {
        # part instance iterator
        set lPartInstsIter [$lPage NewPartInstsIter $lStatus]

        # get the first part inst
        set lInst [$lPartInstsIter NextPartInst $lStatus]
        
        while {$lInst!=$lNullObj} {
            # dynamic cast from DboPartInst to DboPlacedInst
            set lPlacedInst [DboPartInstToDboPlacedInst $lInst]

            if {$lPlacedInst != $lNullObj} {
                # puts $lPlacedInst
                # get part reference & value
                $lPlacedInst GetPartValue $lValue
                $lPlacedInst GetReferenceDesignator $lReference
                # puts "[DboTclHelper_sGetConstCharPtr $lReference] [DboTclHelper_sGetConstCharPtr $lValue]"
                set isResistor [string match "R*" [DboTclHelper_sGetConstCharPtr $lReference]]

                # SPICE Netlist Lines
                set modelName   [string map {" " $pValueDelim} [DboTclHelper_sGetConstCharPtr $lValue]]
                set subcktLine  ".SUBCKT $modelName"
                set pininfoLine "*.PININFO"

                if {$isResistor} {
                    set netlistLine "[DboTclHelper_sGetConstCharPtr $lReference]"
                } else {
                    set netlistLine "X[DboTclHelper_sGetConstCharPtr $lReference]"
                }

                # get the first part pin
                set lPinsIter [$lPlacedInst NewPinsIter $lStatus]
                set lPinName  [DboTclHelper_sMakeCString]
                set lPin      [$lPinsIter NextPin $lStatus]

                while {$lPin != $lNullObj} {
                    # puts $lPin
                    # get pin number, pin name, and net
                    set $lStatus [$lPin GetPinNumber $lPinNumber]
                    set $lStatus [$lPin GetPinName $lPinName]
                    set lNet     [$lPin GetNet $lStatus]
                    # puts $lNet

                    if {$lNet == $lNullObj} {
                        set lNetName [DboTclHelper_sMakeCString "UN$pUConnId"]
                        incr pUConnId -1           
                    } else {
                        set $lStatus [$lNet GetNetName $lNetName]
                    }

                    set subcktLine  [concat $subcktLine  [DboTclHelper_sGetConstCharPtr $lPinNumber]]
                    set pininfoLine [concat $pininfoLine "[DboTclHelper_sGetConstCharPtr $lPinNumber]$pNetNameDelim[DboTclHelper_sGetConstCharPtr $lPinName]"]
                    set netlistLine [concat $netlistLine [DboTclHelper_sGetConstCharPtr $lNetName]]

                    # get the next part inst pin
                    set lPin [$lPinsIter NextPin $lStatus]
                }

                set netlistLine [concat $netlistLine $modelName]
                # puts $netlistFP $pininfoLine
                # puts $netlistFP $netlistLine

                if {$isResistor} {
                    puts "Instance [DboTclHelper_sGetConstCharPtr $lReference] does not need a .SUBCKT model."
                } else {
                    set isRepeated [string match "*$subcktLine*" $pSubCktDef]
                    
                    if {$isRepeated != 1} {
                        puts "Creating .SUBCKT for [DboTclHelper_sGetConstCharPtr $lReference] instance"
                        set pSubCktDef [format "%s%s\n%s\n%s\n\n" $pSubCktDef $subcktLine $pininfoLine ".ENDS"]
                    }
                }

                set pNetlist [format "%s\n%s" $pNetlist $netlistLine]

                incr lInstCnt
            }

            # get the next part inst
            set lInst [$lPartInstsIter NextPartInst $lStatus]
        }

        # get the next page
        set lPage [$lPagesIter NextPage $lStatus]
    }

    delete_DboPartInstPinsIter $lPinsIter
    delete_DboPagePartInstsIter $lPartInstsIter
    delete_DboSchematicPagesIter $lPagesIter
    puts $netlistFP $pSubCktDef
    puts $netlistFP $pNetlist
    puts $netlistFP "* Total parsed components: [expr $lInstCnt - 1]"
    puts $netlistFP ".END"
    close $netlistFP
}
