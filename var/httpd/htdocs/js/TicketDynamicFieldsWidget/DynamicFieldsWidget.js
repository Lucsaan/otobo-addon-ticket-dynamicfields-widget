"use strict";

var Core = Core || {};
Core.Agent = Core.Agent || {};


/**
 * @namespace Core.Agent.DynamicFieldsWidget
 * @memberof Core.Agent
 * @author
 * @description
 *      This namespace contains functions to show dynamic fields if not process ticket with process information .
 */
Core.Agent.DynamicFieldsWidget = (function (TargetNS) {

    // Do not load if is process ticket
    if ($('#DynamicFieldsWidget').length > 0) {
        return;
    }

    /**
     * @name Init
     * @memberof Core.Agent.UserSessions
     * @function
     * @description
     *      This function initializes widget for dynamic fields in ticket
     */
    TargetNS.Init = function () {
        console.log('i bims der dann später die dynamischen Felder rendern lässt....');
        // let URL = Core.Config.Get('Baselink'),
        //     Data = {
        //         Action: 'TicketDynamicFieldsWidgetAJAX',
        //         Subaction: 'GetDynamicFieldsWidget'
        //     };
        //
        // Core.AJAX.FunctionCall(URL, Data, function (Result) {
        //     console.log('Result', Result);
        // });
    }

    Core.Init.RegisterNamespace(TargetNS, 'APP_MODULE');

    return TargetNS;
}(Core.Agent.DynamicFieldsWidget || {}));
