describe('Public Access', () => {
    before(() => {
        cy.create_token();
        cy.logout();
        cy.delete_organization('test-organization');
        cy.create_organization('test-organization', 'Test organization');
        cy.fixture('ckan_dataset.json').then((ckan_dataset) => {
            ckan_dataset.private = false;
            cy.create_dataset(ckan_dataset).should((response) => {
                expect(response.body).to.have.property('success', true);
            });
        });
    });

    after(() => {
        cy.delete_dataset('test-dataset-1');
        cy.delete_organization('test-organization');
        cy.revoke_token();
    });

    it('Cannot access the standard public pages', () => {
        cy.logout();
        cy.request({
            url: '/dataset',
            failOnStatusCode: false,
        }).then((response) => {
            expect(response.status).to.eq(403);
        });

        cy.request({
            url: '/dataset/',
            failOnStatusCode: false,
        }).then((response) => {
            expect(response.status).to.eq(403);
        });
    });

    it('Cannot access the dataset pages', () => {
        cy.request({
            url: '/dataset/test-dataset-1',
            failOnStatusCode: false,
        }).then((response) => {
            expect(response.status).to.eq(404);
        });
    });
});
