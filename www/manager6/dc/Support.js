Ext.define('PVE.dc.Support', {
    extend: 'Ext.panel.Panel',
    alias: 'widget.pveDcSupport',
    onlineHelp: 'getting_help',

    invalidHtml: '<h1>No valid subscription</h1>' + PVE.Utils.noSubKeyHtml,

    communityHtml: Ext.String.format(
        'Please contact <a target="_blank" href="{0}">Blue3</a> for any questions.',
        PVE.Utils.blue3SiteURL,
    ),

    activeHtml: Ext.String.format(
        'Please use our <a target="_blank" href="{0}">support portal</a> for any questions.',
        PVE.Utils.blue3SupportURL,
    ),

    bugzillaHtml: Ext.String.format(
        '<h1>Bug Tracking</h1>Please report any issue through our ' +
            '<a target="_blank" href="{0}">support portal</a>.',
        PVE.Utils.blue3SupportURL,
    ),

    docuHtml: function () {
        return Ext.String.format(
            '<h1>Documentation</h1>' +
                'The Blue3 Cloud Administration Guide is available at ' +
                '<a target="_blank" href="{0}">{0}</a>',
            PVE.Utils.blue3DocsURL,
        );
    },

    updateActive: function (data) {
        var me = this;

        var html = '<h1>' + data.productname + '</h1>' + me.activeHtml;
        html += '<br><br>' + me.docuHtml();
        html += '<br><br>' + me.bugzillaHtml;

        me.update(html);
    },

    updateCommunity: function (data) {
        var me = this;

        var html = '<h1>' + data.productname + '</h1>' + me.communityHtml;
        html += '<br><br>' + me.docuHtml();
        html += '<br><br>' + me.bugzillaHtml;

        me.update(html);
    },

    updateInactive: function (data) {
        var me = this;
        me.update(me.invalidHtml);
    },

    initComponent: function () {
        let me = this;

        let reload = function () {
            Proxmox.Utils.API2Request({
                url: '/nodes/localhost/subscription',
                method: 'GET',
                waitMsgTarget: me,
                failure: function (response, opts) {
                    Ext.Msg.alert(gettext('Error'), response.htmlStatus);
                    me.update(
                        `${gettext('Unable to load subscription status')}: ${response.htmlStatus}`,
                    );
                },
                success: function (response, opts) {
                    let data = response.result.data;
                    if (data?.status.toLowerCase() === 'active') {
                        if (data.level === 'c') {
                            me.updateCommunity(data);
                        } else {
                            me.updateActive(data);
                        }
                    } else {
                        me.updateInactive(data);
                    }
                },
            });
        };

        Ext.apply(me, {
            autoScroll: true,
            bodyStyle: 'padding:10px',
            listeners: {
                activate: reload,
            },
        });

        me.callParent();
    },
});
