package Kernel::Modules::TicketDynamicFieldsWidgetAJAX;

use strict;
use warnings;

use Kernel::System::CheckItem;
use Kernel::System::VariableCheck qw(:all);
use Kernel::Language qw(Translatable);
our $ObjectManagerDisabled = 1;

sub new {
    my ($Type, %Param) = @_;
    my $Self = { %Param };
    bless($Self, $Type);

    $Self->{LayoutObject} = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    $Self->{GroupObject} = $Kernel::OM->Get('Kernel::System::Group');
    $Self->{ConfigObject} = $Kernel::OM->Get('Kernel::Config');
    $Self->{JSONObject} = $Kernel::OM->Get('Kernel::System::JSON');
    $Self->{DynamicFieldObject} = $Kernel::OM->Get('Kernel::System::DynamicField');
    $Self->{DynamicFieldBackendObject} = $Kernel::OM->Get('Kernel::System::DynamicField::Backend');
    $Self->{SessionConfig} = $Kernel::OM->Get('Kernel::Config')->Get('ToolBarUserSessions');
    $Self->{StateControllerConfig} = $Kernel::OM->Get('Kernel::Config')->Get('ToolBarStateController');
    $Self->{SessionObject} = $Kernel::OM->Get('Kernel::System::AuthSession');
    $Self->{UserObject} = $Kernel::OM->Get('Kernel::System::User');
    $Self->{ParamObject} = $Kernel::OM->Get('Kernel::System::Web::Request');
    $Self->{CacheObject} = $Kernel::OM->Get('Kernel::System::Cache');

    $Self->{CacheType} = 'UserSessions_State';
    $Self->{CacheKey} = 'ActualState';

    return $Self;
}

sub Run {
    my ($Self) = @_;

    if ($Self->{Subaction} eq 'GetDynamicFieldsWidget') {
        $Self->GetDynamicFieldsWidget();
    }
}

sub GetDynamicFieldsWidget {
    my ($Self, %Param) = @_;

    my $SessionController = $Self->_InitSessionController();
    my $StateController = $Self->_InitStateController();

    my $Interval = defined $Self->{SessionConfig}->{CountParameter}->{Interval}
        && $Self->{SessionConfig}->{CountParameter}->{Interval} >= 0 ?
        $Self->{SessionConfig}->{CountParameter}->{Interval} : 30;

    my %Response = (
        Position          => $Self->{SessionConfig}->{Position},
        Interval          => int($Interval),
        SessionController => $SessionController,
        StateController   => $StateController
    );

    my $JSON = $Self->{LayoutObject}->JSONEncode(
        Data => \%Response || (),
    );

    return $Self->{LayoutObject}->Attachment(
        ContentType => 'application/json; charset=' . $Self->{LayoutObject}->{Charset},
        Content     => $JSON || '',
        Type        => 'inline',
        NoCache     => 1,
    );
}

sub _LoadState {
    my ($Self, %Param) = @_;

    my $CacheData = $Self->{CacheObject}->Get(
        Type => $Self->{CacheType},
        Key  => $Self->{CacheKey},
    );

    my %StateData = defined($CacheData) ? %$CacheData : ();

    if (!defined($CacheData)) {
        my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
        return if !$DBObject->Prepare(
            SQL   => 'SELECT title, color, icon, change_time, change_by FROM user_sessions_state ORDER BY id DESC',
            Bind  => [],
            Limit => 1,
        );

        while (my @Row = $DBObject->FetchrowArray()) {
            $StateData{Title} = $Row[0];
            $StateData{Color} = $Row[1];
            $StateData{Icon} = $Row[2];
            $StateData{ChangeTime} = $Row[3];

            my %UserData = $Self->{UserObject}->GetUserData(UserID => $Row[4]);
            $StateData{UserFullname} = $UserData{UserFullname};

        }
    }

    # Return empty hash if database has no entries
    if (!%StateData) {
        return %StateData;
    }

    my %ActualUserData = $Self->{UserObject}->GetUserData(UserID => $Self->{UserID});

    my $DateTimeObject = $Kernel::OM->Create(
        'Kernel::System::DateTime',
        ObjectParams => {
            String => $StateData{ChangeTime}
        }
    );

    if (defined($DateTimeObject)) {
        $DateTimeObject->ToTimeZone(
            TimeZone => $ActualUserData{UserTimeZone} || 'Europe/Berlin',
        );

        $StateData{ChangeTime} = $DateTimeObject->Format(Format => '%d.%m.%Y - %H:%M');
    }

    return %StateData;
}

sub _SaveState {
    my ($Self, %Param) = @_;

    my %GetParam = ();
    for my $Needed (qw(Icon Title Color)) {
        $GetParam{$Needed} = $Self->{ParamObject}->GetParam(Param => $Needed);
        if (!defined($GetParam{$Needed})) {
            return {
                Success => 0,
                Error   => "Need $Needed to save new state",
                Data    => []
            };
        }
    }

    my %UserData = $Self->{UserObject}->GetUserData(UserID => $Self->{UserID});
    $GetParam{UserFullname} = $UserData{UserFullname};

    my $DateTimeObject = $Kernel::OM->Create(
        'Kernel::System::DateTime',
        ObjectParams => {}
    );

    $GetParam{ChangeTime} = $DateTimeObject->Format(Format => '%Y-%m-%d %H:%M:%S');

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    my $Success = $DBObject->Do(
        SQL  => '
            INSERT INTO user_sessions_state (title, icon, color, change_by, change_time)
            VALUES (?, ?, ?, ?, current_timestamp)',
        Bind => [ \$GetParam{Title}, \$GetParam{Icon}, \$GetParam{Color}, \$Self->{UserID} ],
    );

    if ($Success) {
        $Self->{CacheObject}->Set(
            Type  => $Self->{CacheType},
            Key   => $Self->{CacheKey},
            Value => \%GetParam,
            TTL   => 60 * 60 * 10
        );
    }

    # Format to actual time zone from user for frontend information
    $DateTimeObject->ToTimeZone(
        TimeZone => $UserData{UserTimeZone} || 'Europe/Berlin',
    );

    $GetParam{ChangeTime} = $DateTimeObject->Format(Format => '%d.%m.%Y - %H:%M');

    my %Response = (
        Success     => $Success,
        ActualState => \%GetParam,
    );

    my $JSON = $Self->{LayoutObject}->JSONEncode(
        Data => \%Response || (),
    );

    return $Self->{LayoutObject}->Attachment(
        ContentType => 'application/json; charset=' . $Self->{LayoutObject}->{Charset},
        Content     => $JSON || '',
        Type        => 'inline',
        NoCache     => 1,
    );

}

sub _InitStateController {
    my ($Self, %Param) = @_;

    my $HasStatePanelPermission = $Self->{GroupObject}->PermissionCheck(
        UserID    => $Self->{UserID},
        GroupName => $Self->{StateControllerConfig}->{Permission}->{StatePanel} || 'user',
        Type      => 'ro'
    );

    my $HasStateControllerPermission = $Self->{GroupObject}->PermissionCheck(
        UserID    => $Self->{UserID},
        GroupName => $Self->{StateControllerConfig}->{Permission}->{StateController} || 'admin',
        Type      => 'ro'
    );

    my @PossibleStates = @{$Self->{StateControllerConfig}->{StateParameter}};
    my %ActualState = $Self->_LoadState();

    if (!%ActualState) {
        %ActualState = %{$PossibleStates[0]};
    }

    return {
        HasStatePanelPermission      => $HasStatePanelPermission,
        HasStateControllerPermission => $HasStateControllerPermission,
        PossibleStates               => \@PossibleStates,
        ActualState                  => \%ActualState
    }
}

sub _InitSessionController {
    my ($Self, %Param) = @_;

    my $HasPermission = $Self->{GroupObject}->PermissionCheck(
        UserID    => $Self->{UserID},
        GroupName => $Self->{SessionConfig}->{Permission}->{Group} || 'admin',
        Type      => 'ro'
    );

    my %SessionResult = ();
    if ($HasPermission) {
        %SessionResult = %{$Self->_GetSessionsResult()};
    }

    return {
        HasPermission => $HasPermission,
        SessionResult => \%SessionResult,
    };
}

sub _Check {
    my ($Self, %Param) = @_;

    my %StateResult = $Self->_LoadState();

    if (!%StateResult) {
        my @PossibleStates = @{$Self->{StateControllerConfig}->{StateParameter}};
        %StateResult = %{$PossibleStates[0]};
    }

    my %Response = (
        SessionResult => $Self->_GetSessionsResult(),
        StateResult   => \%StateResult
    );

    my $JSON = $Self->{LayoutObject}->JSONEncode(
        Data => \%Response || (),
    );

    return $Self->{LayoutObject}->Attachment(
        ContentType => 'application/json; charset=' . $Self->{LayoutObject}->{Charset},
        Content     => $JSON || '',
        Type        => 'inline',
        NoCache     => 1,
    );

}

sub _GetSessionsResult {
    my ($Self, %Param) = @_;

    my %CountParameter = %{$Self->{SessionConfig}->{CountParameter}};
    my @PossibleUserIDs = @{$Self->{SessionConfig}->{PossibleUserIDs}};

    my $Online = {
        User      => {
            Agent    => {},
            Customer => {},
        },
        UserCount => {
            Agent    => 0,
            Customer => 0,
        },
        UserData  => {
            Agent    => {},
            Customer => {},
        },
    };

    # Get all session ids, to generate the logged-in user list.
    my @Sessions = $Self->{SessionObject}->GetAllSessionIDs();

    my $CurSystemDateTimeObject = $Kernel::OM->Create('Kernel::System::DateTime');
    my $SystemTime = $CurSystemDateTimeObject->ToEpoch();
    my $SessionMaxIdleTime = $CountParameter{MaxTimeLastRequest};

    SESSIONID:
    for my $SessionID (@Sessions) {

        next SESSIONID if !$SessionID;

        # get session data
        my %Data = $Self->{SessionObject}->GetSessionIDData(SessionID => $SessionID);

        next SESSIONID if !%Data;
        next SESSIONID if !$Data{UserID};

        # use agent instead of user
        my %AgentData;
        if ($Data{UserType} eq 'User') {
            $Data{UserType} = 'Agent';

            # get user data
            %AgentData = $Self->{UserObject}->GetUserData(
                UserID        => $Data{UserID},
                NoOutOfOffice => 1,
            );
        } else {
            $Data{UserFullname} ||= $Kernel::OM->Get('Kernel::System::CustomerUser')->CustomerName(
                UserLogin => $Data{UserLogin},
            );
        }

        # Skip session, if no last request exists.
        next SESSIONID if !$Data{UserLastRequest};

        # Check the last request / idle time, only if the user is not already shown.
        if (!$Online->{User}->{ $Data{UserType} }->{ $Data{UserID} }) {
            next SESSIONID if $Data{UserLastRequest} + ($SessionMaxIdleTime * 60) < $SystemTime;

            # Count only unique agents and customers, please see bug#13429 for more information.
            $Online->{UserCount}->{ $Data{UserType} }++;
        }

        # Remember the user data, if the user not already exists in the online list or the last request time is newer.
        if (
            !$Online->{User}->{ $Data{UserType} }->{ $Data{UserID} }
                || $Online->{UserData}->{ $Data{UserType} }->{ $Data{UserID} }->{UserLastRequest} < $Data{UserLastRequest}
        ) {
            $Online->{User}->{ $Data{UserType} }->{ $Data{UserID} } = $Data{'UserFullname'};
            $Online->{UserData}->{ $Data{UserType} }->{ $Data{UserID} } = { %Data, %AgentData };
        }
    }

    my $UserOnlineCount = 0;

    for my $UserID (@PossibleUserIDs) {
        my $UserData = $Online->{UserData}->{Agent}->{$UserID};

        next if (!defined($UserData));

        if ($SystemTime - $UserData->{UserLastRequest} < 60 * $SessionMaxIdleTime) {
            $UserOnlineCount++;
        }
    }

    my $Color = $CountParameter{AlertColor} || 'red';
    if ($UserOnlineCount > $CountParameter{WarningCount}) {
        $Color = $CountParameter{NormalColor}
    } elsif ($UserOnlineCount <= $CountParameter{WarningCount} && $UserOnlineCount > $CountParameter{AlertCount}) {
        $Color = $CountParameter{WarningColor};
    }

    return {
        Icon  => $CountParameter{Icon},
        Color => $Color,
        Count => $UserOnlineCount
    };
}

1;
