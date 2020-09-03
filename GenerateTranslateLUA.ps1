#requires -RunAsAdministrator
set-executionpolicy remotesigned -Force
$ErrorActionPreference = "Stop"

#$ScriptRoot = 'T:\@NL Nr5\Language'

Import-Module "$PSScriptRoot\ScriptParameters.ps1" | Out-Null

function IssueCognitiveApiToken {
    
    # Headers required for issuing token
    $tokenUriHeader = @{'Ocp-Apim-Subscription-Key' = $accountKey }
    $tokenUriQuery = "?Subscription-Key=$accountKey"
    $tokenUri = $tokenServiceUrl+$tokenUriQuery

    # Authentication to Cognitive Services - request token.
    $tokenResult = Invoke-WebRequest `
    -Method Post `
    -Headers $tokenUriHeader `
    -UseBasicParsing `
    -Uri "$tokenUri" 

    # Return the authentication token
    return $tokenResult
}

function TranslateQuestItem {
    param (
        [Parameter(Mandatory=$true)]
        [string]$translateText,

        [Parameter(Mandatory=$true)]
        [string]$FromLang,

        [Parameter(Mandatory=$true)]
        [string]$ToLang
    )

    # Build params for API token call
    $token = IssueCognitiveApiToken
    $auth = "Bearer "+$token
    $header = @{Authorization = $auth; 'Ocp-Apim-Subscription-Key' = $accountKey;}

    $translation = TranslateField -translateText $translateText -Header $header -FromLang $fromLang -ToLang $toLang
    #The translated text will be stored in this variable. If you don't want to it to be displayed, remove this line.
    return $translation
}

function TranslateField {
    param (
        [Parameter(Mandatory=$true)]
        [string]$translateText,

        [Parameter(Mandatory=$true)]
        [System.Collections.Hashtable]$Header,
        
        [Parameter(Mandatory=$true)]
        [string]$FromLang,

        [Parameter(Mandatory=$true)]
        [string]$ToLang
    )
    
    # Build translation API query parameters 
    $query = "&from="  + $FromLang
    $query += "&to=" + $ToLang
    $query += "&textType=html"
    $query += "&contentType=application/json"
    $apiUri = $requestTranslationUrl+$query
    
    # Sanitize the field's value into a JSON object
    $obj = @{Text="$translateText" }
    $requestObject = $obj | ConvertTo-Json -depth 100 |
     % { [System.Text.RegularExpressions.Regex]::Unescape($_) } 
         

    try 
    {
        # Call the API
        $result = Invoke-WebRequest `
            -Method Post `
            -Headers $Header `
            -ContentType:"application/json" `
            -Body "[$requestObject]" `
            -UseBasicParsing `
            -Uri "$apiUri" | Select-Object -Expand Content | ConvertFrom-Json

            # Return the translated text
            return $result.translations.text

    } 
    catch [System.Net.WebException]
    {
        # An error occured calling the API
        Write-Host 'Error calling API' -ForegroundColor Red
        Write-Host $Error[0] -ForegroundColor Red
        return $null
    } 
}

function CreateNameSpace
{
    #Create namespace
    $namespace = "$translateLUAScope.$QuestParentDir = {}"
    $namespaceExisting = Select-String -Path $translateFile -Pattern $namespace
    if($namespaceExisting -eq $null) {
        $namespace | Out-File $translateFile -Append default
    }
}

Get-ChildItem -Path $QuestDir -Include *.quest, *.lua -Recurse | ForEach-Object {
    $QuestParentDir = Split-Path (Split-Path $_.FullName -Parent) -Leaf
    CreateNameSpace
    $content = Get-Content $_.FullName
    $tabLine = @()
    $lineNo = 0
    $currLine = 0
    foreach($line in $content)
    {
        if($lineNo -eq 0) {
            $pattern = $line
        }
        $lineNo += 1
    }

    $from = 1
    $to = $lineNo -1
    if($DoCopyToOtherNamespace -eq $true) {
        $fileCopy = @()
        foreach($line in $content)
        {
            $currLine += 1
            if($currLine -gt $from -and $currLine -le $to) {
                $fileCopy += "`t" + $line
                $tabLine += "`t" + $line
            }   
        }
    } else {
        foreach($line in $content) {
            $tabLine += $line
        }
    }

    $questName = $_.Name.Substring(0,$_.Name.IndexOf("."))
    $title_counter=$line_counter=$reward_counter=$letter_counter=$notice_counter=$chat_counter=$npcchat_counter=$select_counter=$quest_counter_counter = 1
    foreach($line in $tabLine) {
        $translateLine = "$translateLUAScope.$QuestParentDir.$QuestName" + "_"
        $executeOutFile = $false
        $skipCounterUpdate = $false

        ##########################
        #General lines <>("...")<>
        ##########################
        if($line -like '*say_title("*' -or $line -like '*say("*' -or $line -like '*say_reward("*' -or $line -like '*send_letter("*' -or $line -like '*notice("*' -or $line -like '*chat("*') {
            $executeOutFile = $true
            if($line -like '*say_title("*') {
                $lineType = "title_$title_counter"
            }
            if($line -like '*say("*') {
                $lineType = "line_$line_counter"
            }
            if($line -like '*say_reward("*') {
                $lineType = "reward_$reward_counter"
            }
            if($line -like '*send_letter("*') {
                $lineType = "letter_$letter_counter"
            }
            if($line -like '*notice("*') {
                $lineType = "notice_$notice_counter"
            }
            if($line -like '*chat("*') {
                $lineType = "chat_$chat_counter"
            }
            $questLine = $translateLine + $lineType
            $translateLine = $translateLine + $lineType + " = "
            $positionStartingBracket = $line.IndexOf('("') + 1
            $positionEndingBracket = $line.LastIndexOf('")') + 1
            $length = $positionEndingBracket - $positionStartingBracket
            $result = $line.substring($positionStartingBracket, $length)
            [string]$translateLine = $translateLine + $result
            if($translateLine -like '*"..*' -or $translateLine -like '*" ..*') {
                #Translate LUA entry
                $parameterstart = $translateLine.IndexOf('"..')
                if($parameterstart -le 0) {
                    $parameterstart = $translateLine.IndexOf('" ..')
                }
                $parameterend = $translateLine.IndexOf('.."')
                if($parameterend -le 0) {
                    $parameterend = $translateLine.IndexOf('.. "')
                    $parameterend += 4
                } else {
                    $parameterend += 3
                }
                $beforeParam = $translateLine.Substring(0,$parameterstart)
                $afterParam = $translateLine.Substring($parameterend)
                $parameter = $translateLine.Substring($parameterstart, ($parameterend - $parameterstart))
                $translateLine = $translateLine.Replace($parameter, "%s")
                #Quest line
                $formatParameter = $parameter -replace '\s',''
                $formatParameter = $formatParameter.Substring(3,($formatParameter.Length - 6))
                $format = 'string.format(' + $questLine + ", " + $formatParameter + ')'
                $tabLine[$tabLine.IndexOf($line)] = $tabLine[$tabLine.IndexOf($line)] -replace [regex]::Escape($result), $format
            }
            else {
                $tabLine[$tabLine.IndexOf($line)] = $tabLine[$tabLine.IndexOf($line)] -replace [regex]::Escape($result), $questline
            }
        }


        ###############################
        #NPC Chat lines <>.chat."..."<>
        ###############################
        if($line -like '*.chat."*') {
            $executeOutFile = $true
            $questLine = $translateLine + "chat_$npcchat_counter"
            $translateLine = $translateLine + "chat_$npcchat_counter = "
            $positionStartingBracket = $line.IndexOf('."') + 1
            $positionEndingBracket = $line.LastIndexOf('"') + 1
            $length = $positionEndingBracket - $positionStartingBracket
            $result = $line.substring($positionStartingBracket, $length)
            [string]$translateLine = $translateLine + $result
            if($translateLine -like '*"..*' -or $translateLine -like '*" ..*') {
                #Translate LUA entry
                $parameterstart = $translateLine.IndexOf('"..')
                if($parameterstart -le 0) {
                    $parameterstart = $translateLine.IndexOf('" ..')
                }
                $parameterend = $translateLine.IndexOf('.."')
                if($parameterend -le 0) {
                    $parameterend = $translateLine.IndexOf('.. "')
                    $parameterend += 4
                } else {
                    $parameterend += 3
                }
                $beforeParam = $translateLine.Substring(0,$parameterstart)
                $afterParam = $translateLine.Substring($parameterend)
                $parameter = $translateLine.Substring($parameterstart, ($parameterend - $parameterstart))
                $translateLine = $translateLine.Replace($parameter, "%s")

                #Quest line
                $formatParameter = $parameter -replace '\s',''
                $formatParameter = $formatParameter.Substring(3,($formatParameter.Length - 6))
                $format = 'string.format(' + $questLine + ", " + $formatParameter + ')'
                $tabLine[$tabLine.IndexOf($line)] = $tabLine[$tabLine.IndexOf($line)] -replace [regex]::Escape($result), $format
            } else {
                $tabLine[$tabLine.IndexOf($line)] = $tabLine[$tabLine.IndexOf($line)] -replace [regex]::Escape($result), $questLine
            }
        }


        #####################################
        #Select lines <>select("A","B","C")<>
        #####################################
        if($line -like '*select("*') {
            $skipCounterUpdate = $true
            $select_counter = 1
            $questLine = ''
            $positionStartingBracket = $line.IndexOf('("') + 1
            $positionEndingBracket = $line.LastIndexOf('")') + 1
            $length = $positionEndingBracket - $positionStartingBracket
            $result = $line.substring($positionStartingBracket, $length)
            $splitResult = $result.Split(',')
            foreach($element in $splitResult) {
                $element = $element.trim()
                #Create Translate LUA entry
                $translateLineBuffer = $translateLine
                $translateLineBuffer = $translateLineBuffer + "select_$select_counter = "
                $questLineBuffer = $translateLine + "select_$select_counter"
                [string]$translateLineBuffer = $translateLineBuffer + $element
                $translateLineBuffer | Out-File $translateFile -Append default

                #create line for quest
                if([string]::IsNullOrEmpty($questLine)) {
                    $questLine = $questLineBuffer
                } else {
                    $questLine = $questLine + ',' + $questLineBuffer
                }
                $select_counter += 1
            }
            $tabLine[$tabLine.IndexOf($line)] = $tabLine[$tabLine.IndexOf($line)] -replace [regex]::Escape($result), $questLine
        }

        ##############################################
        #Questcounter lines <>q.setcounter("..", 10)<>
        ##############################################
        if($line -like '*q.set_counter("*') {
            $executeOutFile = $true
            $questLine = $translateLine + "qsetcounter_$quest_counter_counter"
            $translateLine = $translateLine + "qsetcounter_$quest_counter_counter = "
            $positionStartingBracket = $line.IndexOf('("') + 1
            $positionEndingBracket = $line.LastIndexOf('",') + 1
            $length = $positionEndingBracket - $positionStartingBracket
            $result = $line.substring($positionStartingBracket, $length)
            [string]$translateLine = $translateLine + $result
            if($translateLine -like '*"..*' -or $translateLine -like '*" ..*') {
                #Translate LUA entry
                $parameterstart = $translateLine.IndexOf('"..')
                if($parameterstart -le 0) {
                    $parameterstart = $translateLine.IndexOf('" ..')
                }
                $parameterend = $translateLine.IndexOf('.."')
                if($parameterend -le 0) {
                    $parameterend = $translateLine.IndexOf('.. "')
                    $parameterend += 4
                } else {
                    $parameterend += 3
                }
                $beforeParam = $translateLine.Substring(0,$parameterstart)
                $afterParam = $translateLine.Substring($parameterend)
                $parameter = $translateLine.Substring($parameterstart, ($parameterend - $parameterstart))
                $translateLine = $translateLine.Replace($parameter, "%s")

                #Quest line
                $formatParameter = $parameter -replace '\s',''
                $formatParameter = $formatParameter.Substring(3,($formatParameter.Length - 6))
                $format = 'string.format(' + $questLine + ", " + $formatParameter + ')'
                $tabLine[$tabLine.IndexOf($line)] = $tabLine[$tabLine.IndexOf($line)] -replace [regex]::Escape($result), $format
            } else {
                $tabLine[$tabLine.IndexOf($line)] = $tabLine[$tabLine.IndexOf($line)] -replace [regex]::Escape($result), $questLine
            }
        }

        if($executeOutFile -eq $true)
        {
            $translateLine | Out-File $translateFile -Append default
        }
        if($line -like '*say_title("*') {
            $title_counter += 1
        }
        if($line -like '*say("*') {
            $line_counter += 1
        }
        if($line -like '*say_reward("*') {
            $reward_counter += 1
        }
        if($line -like '*send_letter("*') {
            $letter_counter += 1
        }
        if($line -like '*notice("*') {
            $notice_counter += 1
        }
        if($line -like '*chat("*') {
            $chat_counter += 1
        }
        if($line -like '*q.set_counter("*') {
            $quest_counter_counter += 1
        }
        if($line -like '*.chat."*') {
            $npcchat_counter += 1
        }
        if($line -like '*select("*') {
            $select_counter += 1
        }
    }
    Set-Content $_.FullName -Value $tabLine
    $tabLine = Get-Content $_.FullName
}