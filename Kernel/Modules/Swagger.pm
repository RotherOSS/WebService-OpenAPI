# --
# OTOBO is a web-based ticketing system for service organisations.
# --
# Copyright (C) 2001-2020 OTRS AG, https://otrs.com/
# Copyright (C) 2019-2025 Rother OSS GmbH, https://otobo.io/
# --
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later version.
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.
# --

package Kernel::Modules::Swagger;

use strict;
use warnings;
use JSON;
use Storable          qw(dclone);
use URI::Escape       qw(uri_escape_utf8);
use Types::Serialiser ();

use Kernel::System::VariableCheck qw(:all);
use Kernel::Language              qw(Translatable);

our $ObjectManagerDisabled = 1;

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {%Param};
    bless( $Self, $Type );

    $Self->{ContentlessMethods} = {
        GET     => 1,
        HEAD    => 1,
        DELETE  => 1,
        OPTIONS => 1,
        CONNECT => 1,
        TRACE   => 1,
    };

    $Self->{ContentMethods} = {
        POST  => 1,
        PUT   => 1,
        PATCH => 1,
    };

    # static meta data for otobo webservices

    $Self->{Components} = {
        "securitySchemes" => {
            "SessionID" => {
                "description" => "SessionID requested with UserLogin and Password via CreateSession endpoint",
                "type"        => "apiKey",
                "name"        => "SessionID",
                "in"          => "query",
            }
        },
        "schemas"    => {},
        "parameters" => {},
    };

    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $YAMLObject   = $Kernel::OM->Get('Kernel::System::YAML');
    my $MainObject   = $Kernel::OM->Get('Kernel::System::Main');

    my $Home = $ConfigObject->Get('Home');

    $Self->{MetaData} = {};

    my @WebserviceMetaDescs = glob("$Home/var/webservices/metadata/*.yml");
    for my $MetaData (@WebserviceMetaDescs) {

        my $WebServiceDesc = $MainObject->FileRead( Location => $MetaData );

        local $YAML::XS::Boolean = "JSON::PP";
        my $WebServiceMetaData = $YAMLObject->Load(
            Data => $WebServiceDesc->$*,
        );

        if ( IsHashRefWithData($WebServiceMetaData) ) {

            if ( exists $WebServiceMetaData->{components} ) {

                my $Schemas    = $WebServiceMetaData->{components}->{schemas};
                my $Parameters = $WebServiceMetaData->{components}->{parameters};

                if ( IsHashRefWithData($Schemas) ) {
                    $Self->{Components}->{schemas} = {
                        $Self->{Components}->{schemas}->%*,
                        $Schemas->%*,
                    };
                }

                if ( IsHashRefWithData($Parameters) ) {
                    $Self->{Components}->{parameters} = {
                        $Self->{Components}->{parameters}->%*,
                        $Parameters->%*,
                    };
                }
                delete $WebServiceMetaData->{components};
            }

            $Self->{MetaData} = {
                $Self->{MetaData}->%*,
                $WebServiceMetaData->%*,
            };
        }
    }

    my $DynamicFieldObject = $Kernel::OM->Get('Kernel::System::DynamicField');

    if ( $Self->{Components}->{schemas}->{TicketQuery} ) {

        my $DynamicFieldList = $DynamicFieldObject->DynamicFieldListGet(
            ResultType => 'HASH',
            ObjectType => ['Ticket'],
        );

        for my $DF ( $DynamicFieldList->@* ) {

            my $DFName = "DynamicField_" . $DF->{Name};

            $Self->{Components}->{schemas}->{TicketQuery}->{properties}->{$DFName} = {

                type       => 'object',
                properties => {
                    Empty => {
                        enum => [ 0, 1 ],
                        type => 'integer',
                    },
                    Equals => {
                        type => 'string',
                    },
                    GreaterThan => {
                        type => 'string',
                    },
                    GreaterThanEquals => {
                        type => 'string',
                    },
                    Like => {
                        type => 'string',
                    },
                    SmallerThan => {
                        type => 'string',
                    },
                    SmallerThanEquals => {
                        type => 'string',
                    },
                },
            };
        }
    }

    if ( $Self->{Components}->{schemas}->{ConfigItemQuery} ) {

        my $DynamicFieldList = $DynamicFieldObject->DynamicFieldListGet(
            ResultType => 'HASH',
            ObjectType => ['ITSMConfigItem'],
        );

        for my $DF ( $DynamicFieldList->@* ) {

            my $DFName = "DynamicField_" . $DF->{Name};

            $Self->{Components}->{schemas}->{ConfigItemQuery}->{properties}->{$DFName} = {

                type       => 'object',
                properties => {

                    Empty => {
                        enum => [ 0, 1 ],
                        type => 'integer',
                    },
                    Equals => {
                        type => 'string',
                    },
                    GreaterThan => {
                        type => 'string',
                    },
                    GreaterThanEquals => {
                        type => 'string',
                    },
                    Like => {
                        type => 'string',
                    },
                    SmallerThan => {
                        type => 'string',
                    },
                    SmallerThanEquals => {
                        type => 'string',
                    },
                },
            };
        }
    }

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $ConfigObject  = $Kernel::OM->Get('Kernel::Config');
    my $ParamObject   = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $SessionObject = $Kernel::OM->Get('Kernel::System::AuthSession');

    my $SessionName = $ConfigObject->Get('SessionName') || 'SessionID';
    my $SessionID   = $ParamObject->GetCookie( Key => $SessionName );

    if ( !$SessionID || !$SessionObject->CheckSessionID( SessionID => $SessionID ) ) {

        return $Self->UnAuthorized();
    }

    my $BaseURL = "/otobo/nph-genericinterface.pl/Webservice/";

    my $LayoutObject     = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $WebserviceObject = $Kernel::OM->Get('Kernel::System::GenericInterface::Webservice');
    my $JSONObject       = $Kernel::OM->Get('Kernel::System::JSON');

    my $WebserviceIDs = $WebserviceObject->WebserviceList();

    my @Webservices;
    WS:
    for my $WebserviceID ( keys %$WebserviceIDs ) {

        my $Webservice = $WebserviceObject->WebserviceGet( ID => $WebserviceID );

        # only add valid webservices to OpenAPI spec
        if ( !$Webservice->{ValidID} == 1 ) {
            next WS;
        }

        my $Provider  = $Webservice->{Config}->{Provider};
        my $Transport = $Provider->{Transport};

        # skip SOAP webservices
        if ( $Transport->{Type} ne 'HTTP::REST' ) {
            next WS;
        }

        my $RouteOperationMapping = $Transport->{Config}->{RouteOperationMapping};
        my $Operations            = $Provider->{Operation};

        for my $Operation ( keys %$Operations ) {

            my $OperationType   = $Operations->{$Operation}->{Type};
            my $Description     = $Operations->{$Operation}->{Description};
            my $MappingInbound  = $Operations->{$Operation}->{MappingInbound};
            my $MappingOutbound = $Operations->{$Operation}->{MappingOutbound};
            my $Mapping         = $RouteOperationMapping->{$Operation};
            my $Route           = $Mapping->{Route};
            my $Methods         = $Mapping->{RequestMethod};

            my $PathParams = $Self->PathParams( Route => $Route );

            my $Path = $Route;

            # replace the Otobo path params placeholders (':Param' )
            # with swager path param placeholdes ('{Param}')
            $Path =~ s/:([^:\/]+)/{$1}/g;

            METHOD:
            for my $Method (@$Methods) {

                # if there is inbound mapping configured, the endpoint will
                # be listed, but not usable via Swagger UI
                if ( IsHashRefWithData($MappingInbound) ) {
                    my $Endpoint = {
                        Name        => $Webservice->{Config}->{Description},
                        Method      => $Method,
                        Type        => $OperationType,
                        Route       => $Route,
                        Path        => $BaseURL . $Webservice->{Name} . $Path,
                        PathParams  => $PathParams,
                        Description => "This endpoint has advanced Inbound mapping applied. Unable to generate proper OpenAPI spec. " . $Description,
                        QueryParams => [],
                        Mapping     => 1,
                    };
                    push @Webservices, $Endpoint;
                    next METHOD;
                }

                # add all QueryParams from static metadata,
                # but skip any parameters that are configured as Path parameters
                my @QueryParams;

                # try to fall back to 'GET' if there is no QueryParam info for
                # this method, but the method is one of 'HEAD', 'DELETE', or 'OPTIONS'
                my $MethodToUseForSwaggerSpec = $Method;
                if (
                    $Self->{QueryParams}->{$OperationType}
                    &&
                    !$Self->{QueryParams}->{$OperationType}->{$Method}
                    )
                {
                    if ( exists $Self->{ContentlessMethods}->{$Method} ) {

                        if ( $Self->{QueryParams}->{$OperationType}->{'GET'} ) {
                            $MethodToUseForSwaggerSpec = 'GET';
                        }
                    }
                }

                if (
                    $Self->{MetaData}->{$OperationType}->{QueryParams}
                    &&
                    $Self->{MetaData}->{$OperationType}->{QueryParams}->{$MethodToUseForSwaggerSpec}
                    )
                {

                    my $Params = $Self->{MetaData}->{$OperationType}->{QueryParams}->{$MethodToUseForSwaggerSpec};
                    for my $Param (@$Params) {

                        my $Name = $Param->{name};
                        if ( !$Name && $Param->{'$ref'} ) {

                            my $Ref = $Param->{'$ref'};
                            $Ref =~ s/#\/components\/parameters\///;
                            $Name = $Self->{Components}->{parameters}->{$Ref}->{name};
                        }

                        if ( $Name && !scalar grep {/^$Name$/} @$PathParams ) {
                            push @QueryParams, $Param;
                        }
                    }
                }

                # add request body if method is not of GET|DELETE|HEAD|OPTIONS|CONNECT|TRACE
                my $RequestBody = undef;

                if ( exists $Self->{ContentMethods}->{$Method} )
                {
                    # only if we have static meta data
                    if ( $Self->{MetaData}->{$OperationType}->{RequestBody} ) {

                        $RequestBody = $Self->{MetaData}->{$OperationType}->{RequestBody};
                    }
                }

                # add ws description
                # if there is an outbound mapping, add a note that
                # example responses will not match actual output
                my $ApiDescription = $Description;
                if ( IsHashRefWithData($MappingOutbound) ) {
                    $ApiDescription .= " This endpoint has additional outbound mapping applied, please note actual Output might differ from example responses.";
                }

                my $Endpoint = {
                    Name        => $Webservice->{Name},
                    Method      => $Method,
                    Type        => $OperationType,
                    Route       => $Route,
                    Path        => $BaseURL . uri_escape_utf8( $Webservice->{Name} ) . $Path,
                    PathParams  => $PathParams,
                    Description => $ApiDescription,
                    QueryParams => \@QueryParams,
                    RequestBody => $RequestBody,
                };
                push @Webservices, $Endpoint;
            }
        }
    }

    # generate openAPI spec from list of endpoints
    my $Output = $Self->GenerateSwagger(
        Services => \@Webservices,
    );

    return $LayoutObject->Attachment(
        ContentType => 'text/javascript',
        Content     => $JSONObject->Encode(
            Data     => $Output,
            SortKeys => 1
        ),
        Type    => 'inline',
        NoCache => 1,
    );

}

# helper to extract Path Parameters from Endpoint Route
sub PathParams {
    my ( $Self, %Param ) = @_;
    my $Route = $Param{Route};

    my @PathParams;

    my @Parts = split /\//, $Route;
    for my $Part (@Parts) {

        if ( $Part =~ /^:[^:]+$/ ) {

            my $Param = substr $Part, 1;
            push @PathParams, $Param;
        }
    }
    return \@PathParams;
}

# actually generate an OpenAPI spec document
sub GenerateSwagger {
    my ( $Self, %Param ) = @_;

    my $Services = $Param{Services};

    my $JSONObject = $Kernel::OM->Get('Kernel::System::JSON');

    # static part of document
    my $OpenAPI = {

        "openapi" => "3.0.0",
        "info"    => {
            "title"       => "Otobo Provider REST API",
            "version"     => "11.0.0",
            "description" => "**Contact**: Customers with a support contract can get support at <a href='mailto:support\@otobo.io'>support\@otobo.io</a>, otherwise please contact <a href='mailto:hallo\@otobo.io'>mailto:hallo\@otobo.io</a>. 

**Note on Authentication**:
 - You can authenticate by adding UserLogin/Password for every request. or if you have a CreateSession endpoint configured,
 - call SessionCreate once with UserLogin/Password to get a SessionID, and then specify the SessionID with every request, or
 - set the SessionID for all requests via the 'Authorize' button.

 Note on Date Format:
 - specify date formats like '2025-08-27 10:00:00'

" . $Self->GenerateDynamicFieldInfo(),
            "contact" => {
                "name"  => "Otobo API Support",
                "url"   => "https://doc.otobo.org/manual/admin/11.0/en/content/administration-area/processes-automation/web-services.html",
#                "email" => "info\@otobo.io"
            },
            "version" => "11.0.0",
        },
        "paths" => {},

        "components" => $Self->{Components},
        "security"   => [
            {
                "SessionID" => [],
            }
        ]
    };

    # add each configured webservice to spec document
    for my $Service (@$Services) {

        # params to show in UI
        my $Params = [];

        # add all path parameters
        for my $PathParam ( $Service->{PathParams}->@* ) {

            push @$Params, {

                "name"        => $PathParam,
                "in"          => "path",
                "required"    => $JSONObject->True(),
                "description" => $PathParam,
                "schema"      => {
                    "type" => "string"
                },
            };
        }

        # add the query parameters, if any
        for my $QueryParam ( $Service->{QueryParams}->@* ) {

            push @$Params, $QueryParam;
        }

        # add example responses, unless an inbound mapping was detected
        my $Responses = {};

        #        if( ! $Service->{Mapping}) {
        if ( $Service->{Method} ne 'HEAD' ) {
            $Responses = $Self->{MetaData}->{ $Service->{Type} }->{Responses};
        }

        #       }

        # make sure the path hash exists in document
        if ( !exists $OpenAPI->{paths}->{ $Service->{Path} } ) {
            $OpenAPI->{paths}->{ $Service->{Path} } = {};
        }

        $OpenAPI->{paths}->{ $Service->{Path} }->{ lc $Service->{Method} } = {

            "operationId" => $Service->{Path} . " (" . $Service->{Method} . ")",
            "summary"     => $Service->{Description},
            "parameters"  => $Params,
            "responses"   => $Responses,
            "tags"        => [ $Service->{Name} ],
        };

        if ( $Service->{RequestBody} ) {

            $OpenAPI->{paths}->{ $Service->{Path} }->{ lc $Service->{Method} }->{"requestBody"} = $Service->{RequestBody};
        }
    }

    return $OpenAPI;
}

sub GenerateDynamicFieldInfo {
    my ( $Self, %Param ) = @_;

    my $DynamicFieldObject = $Kernel::OM->Get('Kernel::System::DynamicField');
    my $BackendObject      = $Kernel::OM->Get('Kernel::System::DynamicField::Backend');
    my $LayoutObject       = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    my $DynamicFieldList = $DynamicFieldObject->DynamicFieldListGet(
        ResultType => 'HASH',
        ObjectType => [ 'Ticket', 'Article' ],
    );

    my $DFs = {};

    for my $DF ( $DynamicFieldList->@* ) {

        my $DFName = $DF->{Name};

        my $Values = $BackendObject->PossibleValuesGet(
            DynamicFieldConfig => $DF,
        );

        $DFs->{$DFName} = {
            %$DF,
            Values => [ values %$Values ],
        };
    }

    my $DFCount = scalar keys $DFs->%*;

    if ( !$DFCount ) {
        return '';
    }

    my $Html = '<details>
          <summary>Dynamic Fields</summary>
        <h5>Available Dynamic Fields for Tickets and Articles</h5>
        <table border="1">
        <tr>
            <th>Name</th>
            <th>Type</th>
            <th>Multiple Values?</th>
            <th>Empty Value?</th>
            <th>Possible Values</th>
        </tr>
        <tr>
    ';

    NEXTDF:
    for my $DF ( keys %$DFs ) {

        my $DFConfig = $DFs->{$DF};
        if ( $DFConfig->{InternalField} ) {
#            next NEXTDF;
        }
        my $Values = $DFConfig->{Values};
        $Html .= "<tr><td>&nbsp;";
        $Html .= $DF;
        $Html .= "</td><td>&nbsp;";
        $Html .= $DFConfig->{ObjectType};
        $Html .= "</td><td>&nbsp;";
        $Html .= ( ( exists $DFConfig->{Config}->{MultiValue} ) && $DFConfig->{Config}->{MultiValue} ) ? 'Yes' : 'No';
        $Html .= "</td><td>&nbsp;";
        $Html .= ( ( exists $DFConfig->{Config}->{PossibleNone} ) && $DFConfig->{Config}->{PossibleNone} ) ? 'Yes' : 'No';
        $Html .= "</td><td>&nbsp;";

        if ($Values) {

            my $PossibleValues = join ', ', $Values->@*;
            $PossibleValues = $LayoutObject->Ascii2Html(
                Text           => $PossibleValues,
                HTMLResultMode => 1
            );
            $Html .= $PossibleValues;
        }
        $Html .= "</td></tr>";
    }

    $Html .= '</table></details>';

    return $Html;
}

sub UnAuthorized {
    my ( $Self, %Param ) = @_;

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $JSONObject   = $Kernel::OM->Get('Kernel::System::JSON');

    my $OpenAPI = {

        "openapi" => "3.0.0",
        "info"    => {
            "title"       => "Otobo Provider REST API",
            "version"     => "11.0.0",
            "description" => "Please login into Otobo to view the OpenAPI specification!",
            "contact"     => {
                "name"  => "Otobo API Support",
                "url"   => "https://otobo.io",
                "email" => "info\@otobo.io"
            },
        },
        "paths"      => {},
        "components" => {},
        "security"   => [],
    };

    return $LayoutObject->Attachment(
        ContentType => 'text/javascript',
        Content     => $JSONObject->Encode(
            Data     => $OpenAPI,
            SortKeys => 1
        ),
        Type    => 'inline',
        NoCache => 1,
    );
}

1;
